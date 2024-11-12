// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console, Vm} from "forge-std/Test.sol";
import {HelperConfig} from "../script/HelperConfig.s.sol";
import {DeployTests} from "../script/DeployTests.s.sol";
import {DuelFactory} from "../src/DuelFactory.sol";
import {Duel} from "../src/Duel.sol";
import {DuelOption} from "../src/DuelOption.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract DuelOptionTest is Test {
    // Config contracts
    HelperConfig helperConfig;
    HelperConfig.NetworkConfig config;
    DeployTests deploy;

    // Errors
    error DuelOption__Unauthorized();
    error DuelOption__PayoutFailed();
    error DuelOption__AmountExceeded();
    error DuelOption__FundingTimeEnded();
    error DuelOption__DuelNotExpired();

    // Events
    event PayoutSent(address indexed payoutAddress, uint256 indexed amount);
    event FundsClaimed(address indexed user, uint256 indexed amount);

    // Contracts
    DuelFactory duelFactory;
    Duel duelImplementation;
    Duel duel;
    DuelOption duelOptionA;
    DuelOption duelOptionB;
    address duelImplementationAddress;
    address duelWallet = makeAddr("duelWallet");

    // Users
    address playerA = address(0x1);
    address playerB = address(0x2);
    address judge = address(0x3);

    // Test variables
    uint256 duelFee = 100; // Fee in basis points (1%)
    uint256 fundingDuration = 3 days;
    uint256 decisionLockDuration = 5 days;
    uint256 amount = 1 ether;

    function setUp() public {
        // Set up helper config and deploy scripts
        helperConfig = new HelperConfig();
        config = helperConfig.getConfig();
        deploy = new DeployTests();
        (duelImplementation, duelFactory) = deploy.run();

        duelImplementationAddress = address(duelImplementation);

        // Create a duel via the factory
        vm.deal(playerA, amount);
        vm.startPrank(playerA);

        address duelAddress = duelFactory.createDuel{value: amount}(
            "Test Duel",
            playerA, // payoutA
            playerB,
            amount,
            fundingDuration,
            decisionLockDuration,
            judge
        );
        vm.stopPrank();

        duel = Duel(duelAddress);

        // Get the addresses of DuelOption contracts
        duelOptionA = DuelOption(payable(duel.optionA()));
        duelOptionB = DuelOption(payable(duel.optionB()));
    }

    function testFundingDuelOption() public {
        // Player A has already funded DuelOptionA during duel creation
        // Let's check that the balance is correct
        uint256 balance = address(duelOptionA).balance;
        assertEq(
            balance,
            amount,
            "Incorrect balance in DuelOptionA after creation"
        );

        // Now let's try to fund DuelOptionB
        vm.deal(playerB, amount);
        vm.startPrank(playerB);

        // Send funds to DuelOptionB
        (bool success, ) = address(duelOptionB).call{value: amount}("");
        assertTrue(success, "Funding DuelOptionB failed");

        // Check that the balance is correct
        balance = address(duelOptionB).balance;
        assertEq(
            balance,
            amount,
            "Incorrect balance in DuelOptionB after funding"
        );

        vm.stopPrank();
    }

    function testFundingDuelOptionAmountExceeded() public {
        // Try to overfund DuelOptionA
        vm.deal(playerA, amount + 0.1 ether);
        vm.startPrank(playerA);

        vm.expectRevert(DuelOption__AmountExceeded.selector);

        // Attempt to send more than the amount
        (bool success, ) = address(duelOptionA).call{value: amount + 0.1 ether}(
            ""
        );
        // The call will revert

        vm.stopPrank();
    }

    function testFundingDuelOptionAfterFundingTimeEnded() public {
        // Warp time beyond funding duration
        uint256 creationTime = duelOptionB.creationTime();
        uint256 fundingTime = duelOptionB.fundingDuration();
        vm.warp(creationTime + fundingTime + 1);

        // Try to fund DuelOptionB after funding time ended
        vm.deal(playerB, amount);
        vm.startPrank(playerB);

        vm.expectRevert(DuelOption__FundingTimeEnded.selector);

        (bool success, ) = address(duelOptionB).call{value: amount}("");
        // The call will revert

        vm.stopPrank();
    }

    function testSendPayoutByUnauthorizedCaller() public {
        // Attempt to call sendPayout by someone other than the duelAddress
        vm.prank(playerA);

        vm.expectRevert(DuelOption__Unauthorized.selector);

        duelOptionA.sendPayout(payable(playerA), duelWallet);
    }

    function testSendPayout() public {
        // Simulate the duel deciding a winner and calling sendPayout
        // First, fund DuelOptionB
        vm.deal(playerB, amount);
        vm.startPrank(playerB);
        (bool success, ) = address(duelOptionB).call{value: amount}("");
        assertTrue(success, "Funding DuelOptionB failed");
        vm.stopPrank();

        // Ensure that both DuelOption contracts have the correct balance
        assertEq(
            address(duelOptionA).balance,
            amount,
            "Incorrect balance in DuelOptionA"
        );
        assertEq(
            address(duelOptionB).balance,
            amount,
            "Incorrect balance in DuelOptionB"
        );

        // Now, we need to impersonate the Duel contract to call sendPayout
        vm.prank(address(duel));

        // For simplicity, let's assume playerA is the winner
        address payable payoutAddress = payable(playerA);

        // Record balances before payout
        uint256 balanceBeforePayoutAddress = payoutAddress.balance;
        uint256 balanceBeforeDuelWallet = duelWallet.balance;

        // Call sendPayout on both DuelOption contracts
        duelOptionA.sendPayout(payoutAddress, duelWallet);
        vm.prank(address(duel));
        duelOptionB.sendPayout(payoutAddress, duelWallet);

        // Check that the payoutAddress received the correct amount
        uint256 totalAmount = amount * 2;
        uint256 expectedFee = (totalAmount * duelFee) / 10000;
        uint256 expectedPayout = totalAmount - expectedFee;

        uint256 payoutReceived = payoutAddress.balance -
            balanceBeforePayoutAddress;
        assertEq(
            payoutReceived,
            expectedPayout,
            "Incorrect payout amount received"
        );

        // Check that the duelWallet received the correct fee
        uint256 feeReceived = duelWallet.balance - balanceBeforeDuelWallet;
        assertEq(feeReceived, expectedFee, "Incorrect fee amount received");
    }

    function testClaimFunds() public {
        // Assume duel has expired
        // Warp time beyond funding duration and decision period
        uint256 creationTime = duel.creationTime();
        uint256 fundingDurationValue = duel.fundingDuration();
        uint256 decisionLockDurationValue = duel.decisionLockDuration();
        uint256 decisionDuration = fundingDurationValue;

        uint256 expiryTime = creationTime +
            decisionLockDurationValue +
            decisionDuration +
            1;
        vm.warp(expiryTime);

        // Update duel status
        duel.updateStatus();

        // Ensure the duel is expired or finished
        assertTrue(
            duel.duelExpiredOrFinished(),
            "Duel is not expired or finished"
        );

        // Player A attempts to claim funds from DuelOptionA
        vm.startPrank(playerA);
        uint256 balanceBefore = playerA.balance;
        duelOptionA.claimFunds();
        uint256 amountClaimed = playerA.balance - balanceBefore;

        // Check that the amount claimed is correct
        assertEq(amountClaimed, amount, "Incorrect amount claimed by playerA");

        vm.stopPrank();
    }

    function testClaimFundsWhenDuelNotExpired() public {
        // Attempt to claim funds before the duel is expired
        vm.startPrank(playerA);

        vm.expectRevert(DuelOption__DuelNotExpired.selector);

        duelOptionA.claimFunds();

        vm.stopPrank();
    }

    function testMultipleFunders() public {
        uint256 testAmount = 1 ether;
        uint256 testFundingTime = 3 days;
        uint256 testDuelFee = 100; // 1%

        // Create a new DuelOption instance for testing
        DuelOption testDuelOption = new DuelOption(
            address(duel), // duelAddress
            testAmount, // amount
            testFundingTime, // fundingTime
            testDuelFee,
            playerA // initialFunder
        );

        address funder1 = address(0x4);
        address funder2 = address(0x5);

        vm.deal(funder1, 0.5 ether);
        vm.deal(funder2, 0.5 ether);

        // Fund testDuelOption with two different addresses
        vm.startPrank(funder1);
        (bool success1, ) = address(testDuelOption).call{value: 0.5 ether}("");
        assertTrue(success1, "Funding by funder1 failed");
        vm.stopPrank();

        vm.startPrank(funder2);
        (bool success2, ) = address(testDuelOption).call{value: 0.5 ether}("");
        assertTrue(success2, "Funding by funder2 failed");
        vm.stopPrank();

        // Check balances
        assertEq(
            testDuelOption.balances(funder1),
            0.5 ether,
            "Incorrect balance for funder1"
        );
        assertEq(
            testDuelOption.balances(funder2),
            0.5 ether,
            "Incorrect balance for funder2"
        );

        // Ensure the contract's total balance equals the amount
        assertEq(
            address(testDuelOption).balance,
            testAmount,
            "Incorrect total balance in testDuelOption"
        );
    }
}
