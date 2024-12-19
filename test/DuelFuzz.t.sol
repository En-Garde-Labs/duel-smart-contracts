// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";
import {DeployTests} from "script/DeployTests.s.sol";
import {DuelFactory} from "../src/DuelFactory.sol";
import {Duel} from "../src/Duel.sol";
import {DuelOption} from "../src/DuelOption.sol";
import {IDuel} from "../src/Duel.sol";
import {SigUtils} from "./SigUtils.sol";

error DuelOption__AmountExceeded();
error DuelImplementation__NotDecisionPeriod();

contract DuelFuzzTest is Test {
    HelperConfig helperConfig;
    HelperConfig.NetworkConfig config;
    DeployTests deploy;

    // Contracts
    DuelFactory duelFactory;
    Duel duel;
    DuelOption duelOptionA;
    DuelOption duelOptionB;
    SigUtils sigUtils;

    // Test variables
    address playerA = address(0x1);
    address playerB = address(0x2);
    address judge = address(0x3);
    address invitationSigner = vm.addr(0x4);
    uint256 amount = 0.01 ether;
    uint256 creationTime = block.timestamp;
    uint256 fundingDuration = 1 days;
    uint256 decisionLockDuration = 2 days;
    uint256 duelFee = 100; // 1% fee

    function setUp() public {
        helperConfig = new HelperConfig();
        config = helperConfig.getConfig();
        deploy = new DeployTests();
        (duel, duelFactory) = deploy.run();

        address duelAddress = duelFactory.createDuel{value: amount}(
            "Test Duel",
            playerA,
            amount,
            fundingDuration,
            decisionLockDuration,
            judge,
            invitationSigner
        );

        duel = Duel(duelAddress);
        duelOptionA = DuelOption(payable(duel.optionA()));
        duelOptionB = DuelOption(payable(duel.optionB()));
        (
            ,
            string memory name,
            string memory version,
            uint256 chainId,
            address verifyingContract,
            ,
        ) = duel.eip712Domain();
        sigUtils = new SigUtils(name, version, chainId, verifyingContract);
    }

    // 1. Funding Limit Exceeded
    function testFuzzFundingLimit(uint256 fundingAmount) public {
        // Adjust fundingAmount to be between 0.01 ether and the target `amount`
        fundingAmount = bound(fundingAmount, 0.01 ether, amount);

        // Fund playerB and initiate prank
        vm.deal(playerB, fundingAmount);
        vm.startPrank(playerB);

        // Determine remaining fundable amount based on current balance
        uint256 currentBalance = address(duelOptionA).balance;
        uint256 availableFunding = currentBalance < amount
            ? amount - currentBalance
            : 0;

        // If fundingAmount exceeds availableFunding, expect a revert due to funding limit exceeded
        if (fundingAmount > availableFunding) {
            vm.expectRevert(DuelOption__AmountExceeded.selector);
            (bool success, ) = address(duelOptionA).call{value: fundingAmount}(
                ""
            );
        } else {
            // Within funding limit, expect the funding to succeed
            (bool success, ) = address(duelOptionA).call{value: fundingAmount}(
                ""
            );
            assertTrue(success, "Funding within limit failed");
        }

        vm.stopPrank();
    }

    // 2. Balances Tracking Invariant
    function testFuzzBalancesTracking(
        uint256 funder1Amount,
        uint256 funder2Amount
    ) public {
        // Limit each funding amount so their sum does not exceed `amount`
        funder1Amount = bound(funder1Amount, 0, 0);
        funder2Amount = bound(funder2Amount, 0, 0);

        address funder1 = address(0x4);
        address funder2 = address(0x5);

        uint256 startingBalance = address(duelOptionA).balance;

        // Fund playerB with initial balance for each funder
        vm.deal(funder1, funder1Amount);
        vm.deal(funder2, funder2Amount);

        // Funder 1 funds Option A
        vm.startPrank(funder1);
        (bool success1, ) = address(duelOptionA).call{value: funder1Amount}("");
        assertTrue(success1, "Funding by funder1 failed");
        vm.stopPrank();

        // Funder 2 funds Option A
        vm.startPrank(funder2);
        (bool success2, ) = address(duelOptionA).call{value: funder2Amount}("");
        assertTrue(success2, "Funding by funder2 failed");
        vm.stopPrank();

        // Calculate expected total balance from funders
        uint256 totalTrackedBalance = startingBalance + duelOptionA.balances(funder1) +
            duelOptionA.balances(funder2);
        uint256 actualContractBalance = address(duelOptionA).balance;

        // Verify that tracked balances match the contract balance
        assertEq(
            totalTrackedBalance,
            actualContractBalance,
            "Tracked balances mismatch contract balance"
        );
    }

    // 3. Active Status Conditions
    function testFuzzActiveStatusConditions(
        bool playerBAccepts,
        bool judgeAccepts,
        bool withinFundingPeriod
    ) public {
        // Simulate playerB's acceptance if within the funding period
        if (playerBAccepts) {
            SigUtils.Invitation memory invitation = SigUtils.Invitation({
                duelId: duel.duelId(),
                nonce: 1,
                playerB: playerB
            });
            bytes32 digest = sigUtils.getTypedDataHash(invitation);

            (uint8 v, bytes32 r, bytes32 s) = vm.sign(0x4, digest);

            // Concatenate r, s, and v into a single 65-byte signature
            bytes memory signature = abi.encodePacked(r, s, v);
            vm.deal(playerB, amount);
            vm.startPrank(playerB);
            duel.playerBAccept{value: amount}(playerB, 1, signature);
            duel.updateStatus(); // Manually trigger status update after acceptance
            vm.stopPrank();
        }

        // Simulate judge's acceptance if within the funding period
        if (judgeAccepts) {
            vm.startPrank(judge);
            duel.judgeAccept();
            duel.updateStatus(); // Manually trigger status update after acceptance
            vm.stopPrank();
        }

        if (!withinFundingPeriod) {
            vm.warp(creationTime + fundingDuration + 1);
            duel.updateStatus();
        }

        // Check duel's expired or finished status against expected active status
        bool duelStatus = duel.duelExpiredOrFinished();

        bool expectedActive;
        if (withinFundingPeriod) {
            expectedActive = true;
        } else {
            if (playerBAccepts && judgeAccepts) {
                expectedActive = true;
            } else {
                expectedActive = false;
            }
        }

        assertEq(
            !duelStatus,
            expectedActive,
            "Active state mismatch within funding period"
        );
    }

    // 4. Payout Distribution
    function testFuzzPayoutDistribution(uint256 extraAmount) public {
        extraAmount = bound(extraAmount, 0, amount);

        vm.deal(playerB, amount + extraAmount);
        vm.startPrank(playerB);
        (bool success, ) = address(duelOptionB).call{value: amount}("");
        assertTrue(success, "Funding DuelOptionB failed");
        vm.stopPrank();

        address payable payoutAddress = payable(playerA);
        address payable duelWallet = payable(makeAddr("duelWallet"));

        uint256 payoutBefore = payoutAddress.balance;
        uint256 duelWalletBefore = duelWallet.balance;
        uint256 totalBalance = address(duelOptionA).balance +
            address(duelOptionB).balance;

        vm.prank(address(duel));
        duelOptionA.sendPayout(payoutAddress, duelWallet);
        vm.prank(address(duel));
        duelOptionB.sendPayout(payoutAddress, duelWallet);

        uint256 expectedFee = (totalBalance * duelFee) / 10000;
        uint256 expectedPayout = totalBalance - expectedFee;

        assertEq(
            payoutAddress.balance - payoutBefore,
            expectedPayout,
            "Incorrect payout"
        );
        assertEq(
            duelWallet.balance - duelWalletBefore,
            expectedFee,
            "Incorrect fee"
        );
    }

    // 5. Judge Decision Lock
    function testFuzzJudgeDecisionLock(uint256 warpTime) public {
        warpTime = bound(warpTime, 1, decisionLockDuration * 2);

        // Warp to simulate time passing
        vm.warp(creationTime + warpTime);
        vm.startPrank(judge);

        address winner = duel.optionA();

        // Check if the judge should be able to decide, considering the time and acceptances
        bool withinDecisionPeriod = warpTime >= decisionLockDuration;
        bool bothAccepted = duel.playerBAccepted() && duel.judgeAccepted();
        bool shouldSucceed = withinDecisionPeriod && bothAccepted;

        // Expected behavior based on conditions
        if (shouldSucceed) {
            duel.judgeDecide(winner); // Should succeed if both conditions are met
        } else {
            // Expect revert if we're not within the decision period or duel has expired
            vm.expectRevert();
            duel.judgeDecide(winner);
        }

        vm.stopPrank();
    }
}
