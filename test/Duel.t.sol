// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console, Vm} from "forge-std/Test.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";
import {DeployTests} from "script/DeployTests.s.sol";
import {DuelFactory} from "../src/DuelFactory.sol";
import {Duel} from "../src/Duel.sol";
import {DuelOption} from "../src/DuelOption.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IDuel} from "../src/Duel.sol";

contract DuelTest is Test {
    // Config contracts
    HelperConfig helperConfig;
    HelperConfig.NetworkConfig config;
    DeployTests deploy;

    // Errors
    error DuelImplementation__OnlyFactory();
    error DuelImplementation__OnlyJudge();
    error DuelImplementation__OnlyPlayerB();
    error DuelImplementation__FundingDurationExceeded();
    error DuelImplementation__AlreadyAccepted(address);
    error DuelImplementation__NotDecisionPeriod();
    error DuelImplementation__InvalidETHValue();
    error DuelImplementation__FundingFailed();
    error DuelImplementation__InvalidWinner();
    error DuelImplementation__PayoutFailed();
    error DuelImplementation__DuelExpired();
    error DuelImplementation__Unauthorized();

    // Events
    event ParticipantAccepted(address indexed participant);
    event PayoutAddressSet(address indexed player, address indexed payoutAddress);
    event DuelCompleted(address indexed winner);
    event DuelExpired();
    event PayoutSent();

    // Contracts
    DuelFactory duelFactory;
    Duel duelImplementation;
    Duel duelWithJudge;
    Duel duelNoJudge;
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

    function setUp() public {
        helperConfig = new HelperConfig();
        config = helperConfig.getConfig();
        deploy = new DeployTests();
        (duelImplementation, duelFactory) = deploy.run();

        duelImplementationAddress = address(duelImplementation);

        duelWithJudge = Duel(createDuelWithJudge(playerA));
        duelNoJudge = Duel(createDuelNoJudge(playerA));
    }

    function createDuelWithJudge(address player) public returns (address) {
        // Provide ETH to player
        vm.deal(player, 1 ether);
        vm.startPrank(player);

        // Player creates a duel
        address duelWithJudgeAddr = duelFactory.createDuel{value: 1 ether}(
            "Test Duel",
            playerA, // payoutA
            playerB,
            1 ether, // amount
            fundingDuration, // fundingDuration
            decisionLockDuration, // decisionLockDuration
            judge
        );
        vm.stopPrank();

        return duelWithJudgeAddr;
    }

    function createDuelNoJudge(address player) public returns (address) {
        // Provide ETH to player
        vm.deal(player, 1 ether);
        vm.startPrank(player);

        // Player creates a duel with no judge
        address duelNoJudgeAddr = duelFactory.createDuel{value: 1 ether}(
            "Test Duel No Judge",
            playerA, // payoutA
            playerB,
            1 ether, // amount
            fundingDuration, // fundingDuration
            decisionLockDuration, // decisionLockDuration
            address(0) // No judge
        );
        vm.stopPrank();

        return duelNoJudgeAddr;
    }

    function testPlayerASetPayoutAddress() public {
        // Start impersonating playerA
        vm.startPrank(playerA);

        // Player A sets payout address
        duelWithJudge.setPayoutAddress(playerA);

        // Check that payoutAddresses[playerA] is set correctly
        assertEq(duelWithJudge.payoutAddresses(playerA), playerA);

        vm.stopPrank();
    }

    function testPlayerBAccept() public {
        // Start impersonating playerB
        vm.startPrank(playerB);

        // Provide ETH to playerB
        vm.deal(playerB, 1 ether);

        // Player B accepts the duel and sets payout address
        vm.expectEmit(true, false, false, false);
        emit ParticipantAccepted(playerB);
        duelWithJudge.playerBAccept{value: 1 ether}(playerB); // Passing playerB as payout address

        // Check that playerBAccepted is true
        assertTrue(duelWithJudge.playerBAccepted());

        // Check that payoutAddresses[playerB] is set correctly
        assertEq(duelWithJudge.payoutAddresses(playerB), playerB);

        vm.stopPrank();
    }

    function testJudgeAccept() public {
        // Start impersonating judge
        vm.startPrank(judge);

        // Judge accepts the duel
        vm.expectEmit(true, false, false, false);
        emit ParticipantAccepted(judge);
        duelWithJudge.judgeAccept();

        // Check that judgeAccepted is true
        assertTrue(duelWithJudge.judgeAccepted());

        vm.stopPrank();
    }

    function testDuelBecomesActiveAfterAcceptance() public {
        // Player A sets payout address
        vm.startPrank(playerA);
        duelWithJudge.setPayoutAddress(playerA);
        vm.stopPrank();

        // Player B accepts
        vm.startPrank(playerB);
        vm.deal(playerB, 1 ether);
        duelWithJudge.playerBAccept{value: 1 ether}(playerB); // Passing playerB as payout address
        vm.stopPrank();

        // Judge accepts
        vm.startPrank(judge);
        duelWithJudge.judgeAccept();
        vm.stopPrank();

        // Check that the duel is active
        assertTrue(duelWithJudge.judgeAccepted());
        assertTrue(duelWithJudge.playerBAccepted());
        assertFalse(duelWithJudge.duelExpiredOrFinished());
    }

    function testJudgeDecide() public {
        // Players and judge accept to activate the duel
        testDuelBecomesActiveAfterAcceptance();

        // Warp to decision period
        uint256 creationTime = duelWithJudge.creationTime();
        uint256 decisionLockDurationValue = duelWithJudge.decisionLockDuration();

        uint256 decisionStartTime = creationTime + decisionLockDurationValue;

        vm.warp(decisionStartTime + 1);

        // Start impersonating judge
        vm.startPrank(judge);

        // Judge decides the winner (Option A)
        vm.expectEmit(true, false, false, false);
        emit DuelCompleted(duelWithJudge.optionA());
        duelWithJudge.judgeDecide(duelWithJudge.optionA());

        // Check that duelExpiredOrFinished is true
        assertTrue(duelWithJudge.duelExpiredOrFinished());
        assertTrue(duelWithJudge.decisionMade());

        vm.stopPrank();
    }

    function testPlayersAgree() public {
        // Use duel with no judge
        duelNoJudge = Duel(createDuelNoJudge(playerA));

        // Player A sets payout address
        vm.startPrank(playerA);
        duelNoJudge.setPayoutAddress(playerA);
        vm.stopPrank();

        // Player B accepts
        vm.startPrank(playerB);
        vm.deal(playerB, 1 ether);
        duelNoJudge.playerBAccept{value: 1 ether}(playerB); // Passing playerB as payout address
        vm.stopPrank();

        // Duel should be active now
        assertTrue(duelNoJudge.playerBAccepted());
        assertFalse(duelNoJudge.duelExpiredOrFinished());

        // Warp to decision period
        uint256 creationTime = duelNoJudge.creationTime();
        uint256 decisionLockDurationValue = duelNoJudge.decisionLockDuration();

        uint256 decisionStartTime = creationTime + decisionLockDurationValue;

        vm.warp(decisionStartTime + 1);

        // Players agree on the winner (Option A)
        vm.startPrank(playerA);
        duelNoJudge.playersAgree(duelNoJudge.optionA());
        vm.stopPrank();

        vm.startPrank(playerB);
        duelNoJudge.playersAgree(duelNoJudge.optionA());
        vm.stopPrank();

        // Check that duelExpiredOrFinished is true
        assertTrue(duelNoJudge.duelExpiredOrFinished());
        assertTrue(duelNoJudge.decisionMade());
    }

    function testUpdateStatusToExpired() public {
        // Warp to after funding duration
        uint256 creationTime = duelWithJudge.creationTime();
        uint256 fundingDurationValue = duelWithJudge.fundingDuration();

        vm.warp(creationTime + fundingDurationValue + 1);

        // Update status
        duelWithJudge.updateStatus();

        // Check that duelExpiredOrFinished is true
        assertTrue(duelWithJudge.duelExpiredOrFinished());
    }
}