// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Test, console, Vm } from "forge-std/Test.sol";
import { HelperConfig } from "script/HelperConfig.s.sol";
import { DeployTests } from "script/DeployTests.s.sol";
import { DuelFactory } from "../src/DuelFactory.sol";
import { Duel } from "../src/Duel.sol";
import { DuelOption } from "../src/DuelOption.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { IDuel } from "../src/Duel.sol";
import { SigUtils } from "./SigUtils.sol";

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
    error DuelImplementation__UsedNonce();

    // Events
    event ParticipantAccepted(address indexed participant);
    event PayoutAddressSet(address indexed player, address indexed payoutAddress);
    event DuelCompleted(address indexed winner);
    event DuelExpired();
    event PayoutSent();

    // Contracts
    DuelFactory duelFactory;
    Duel duelImplementation;
    Duel duel;
    SigUtils sigUtils;
    address duelImplementationAddress;
    address duelWallet = makeAddr("duelWallet");

    // Users
    address playerA = address(0x1);
    address playerB = address(0x2);
    address judge = address(0x3);
    address invitationSigner = vm.addr(0x4);

    // Test variables
    uint256 duelFee = 100; // Fee in basis points (1%)
    uint256 fundingDuration = 3 days;
    uint256 decisionLockDuration = 5 days;
    uint256 nonce = 1;

    function setUp() public {
        helperConfig = new HelperConfig();
        config = helperConfig.getConfig();
        deploy = new DeployTests();
        (duelImplementation, duelFactory) = deploy.run();

        duelImplementationAddress = address(duelImplementation);

        duel = Duel(createDuel(playerA));
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

    function createDuel(address player) public returns (address) {
        // Provide ETH to player
        vm.deal(player, 1 ether);
        vm.startPrank(player);

        // Player creates a duel
        address duelWithJudgeAddr = duelFactory.createDuel{ value: 1 ether }(
            "Test Duel",
            playerA, // payoutA
            1 ether, // amount
            fundingDuration, // fundingDuration
            decisionLockDuration, // decisionLockDuration
            invitationSigner,
            "1"
        );
        vm.stopPrank();

        return duelWithJudgeAddr;
    }

    function testPlayerASetPayoutAddress() public {
        // Start impersonating playerA
        vm.startPrank(playerA);

        // Player A sets payout address
        duel.setPayoutAddress(playerA);

        // Check that payoutAddresses[playerA] is set correctly
        assertEq(duel.payoutAddresses(playerA), playerA);

        vm.stopPrank();
    }

    function testPlayerBAccept() public {
        SigUtils.PlayerBInvitation memory invitation = SigUtils.PlayerBInvitation({
            duelId: duel.duelId(),
            nonce: nonce,
            playerB: playerB
        });
        bytes32 digest = sigUtils.getPlayerBTypedDataHash(invitation);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(0x4, digest);

        // Concatenate r, s, and v into a single 65-byte signature
        bytes memory signature = abi.encodePacked(r, s, v);

        // Start impersonating playerB
        vm.startPrank(playerB);

        // Provide ETH to playerB
        vm.deal(playerB, 1 ether);

        // Player B accepts the duel and sets payout address
        vm.expectEmit(true, false, false, false);
        emit ParticipantAccepted(playerB);

        duel.playerBAccept{ value: 1 ether }(playerB, nonce, signature); // Passing playerB as payout address

        // Check that the playerB address is set correctly
        assertEq(duel.playerB(), playerB);

        // Check that playerBAccepted is true
        assertTrue(duel.playerBAccepted());

        // Check that payoutAddresses[playerB] is set correctly
        assertEq(duel.payoutAddresses(playerB), playerB);

        vm.stopPrank();
        nonce++;
    }

    function testPlayerBAcceptReplay() public {
        SigUtils.PlayerBInvitation memory invitation = SigUtils.PlayerBInvitation({
            duelId: duel.duelId(),
            nonce: nonce,
            playerB: playerB
        });
        bytes32 digest = sigUtils.getPlayerBTypedDataHash(invitation);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(0x4, digest);

        // Concatenate r, s, and v into a single 65-byte signature
        bytes memory signature = abi.encodePacked(r, s, v);

        // Start impersonating playerB
        vm.startPrank(playerB);
        vm.deal(playerB, 2 ether);
        duel.playerBAccept{ value: 1 ether }(playerB, nonce, signature); // Passing playerB as payout address

        vm.expectRevert();
        duel.playerBAccept{ value: 1 ether }(playerB, nonce, signature); // Passing playerB as payout address
        vm.stopPrank();

        nonce++;
    }

    function testJudgeAccept() public {
        SigUtils.JudgeInvitation memory invitation = SigUtils.JudgeInvitation({
            duelId: duel.duelId(),
            nonce: nonce,
            judge: judge
        });
        bytes32 digest = sigUtils.getJudgeTypedDataHash(invitation);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(0x4, digest);
        bytes memory signature = abi.encodePacked(r, s, v);

        // Start impersonating judge
        vm.startPrank(judge);

        // Judge accepts the duel
        vm.expectEmit(true, false, false, false);
        emit ParticipantAccepted(judge);
        duel.judgeAccept(nonce, signature);

        // Check that judgeAccepted is true
        assertTrue(duel.judgeAccepted());

        // Check that judge is set correctly
        assertEq(duel.judge(), judge);

        vm.stopPrank();
        nonce++;
    }

    function testDuelBecomesActiveAfterAcceptance() public {
        // Player A sets payout address
        vm.startPrank(playerA);
        duel.setPayoutAddress(playerA);
        vm.stopPrank();

        // Judge accepts
        SigUtils.PlayerBInvitation memory playerBInvitation = SigUtils.PlayerBInvitation({
            duelId: duel.duelId(),
            nonce: nonce,
            playerB: playerB
        });
        bytes32 digestPlayerB = sigUtils.getPlayerBTypedDataHash(playerBInvitation);
        (uint8 vp, bytes32 rp, bytes32 sp) = vm.sign(0x4, digestPlayerB);
        bytes memory playerBSignature = abi.encodePacked(rp, sp, vp);

        // Player B accepts
        vm.startPrank(playerB);
        vm.deal(playerB, 1 ether);
        duel.playerBAccept{ value: 1 ether }(playerB, 1, playerBSignature); // Passing playerB as payout address
        vm.stopPrank();

        nonce++;

        // Judge accepts
        SigUtils.JudgeInvitation memory judgeInvitation = SigUtils.JudgeInvitation({
            duelId: duel.duelId(),
            nonce: nonce,
            judge: judge
        });
        bytes32 digestJudge = sigUtils.getJudgeTypedDataHash(judgeInvitation);
        (uint8 vj, bytes32 rj, bytes32 sj) = vm.sign(0x4, digestJudge);
        bytes memory judgeSignature = abi.encodePacked(rj, sj, vj);

        vm.startPrank(judge);
        duel.judgeAccept(nonce, judgeSignature);
        vm.stopPrank();

        // Check that the duel is active
        assertTrue(duel.judgeAccepted());
        assertTrue(duel.playerBAccepted());
        assertFalse(duel.duelExpiredOrFinished());
    }

    function testJudgeDecide() public {
        // Players and judge accept to activate the duel
        testDuelBecomesActiveAfterAcceptance();

        // Warp to decision period
        uint256 creationTime = duel.creationTime();
        uint256 decisionLockDurationValue = duel.decisionLockDuration();

        uint256 decisionStartTime = creationTime + decisionLockDurationValue;

        vm.warp(decisionStartTime + 1);

        // Start impersonating judge
        vm.startPrank(judge);

        // Judge decides the winner (Option A)
        vm.expectEmit(true, false, false, false);
        emit DuelCompleted(duel.optionA());
        duel.judgeDecide(duel.optionA());

        // Check that duelExpiredOrFinished is true
        assertTrue(duel.duelExpiredOrFinished());
        assertTrue(duel.decisionMade());

        vm.stopPrank();
    }

    function testNoJudgePlayersAgreeOnWinner() public {
        // Player A sets payout address
        vm.startPrank(playerA);
        duel.setPayoutAddress(playerA);
        vm.stopPrank();

        SigUtils.PlayerBInvitation memory invitation = SigUtils.PlayerBInvitation({
            duelId: duel.duelId(),
            nonce: nonce,
            playerB: playerB
        });
        bytes32 digest = sigUtils.getPlayerBTypedDataHash(invitation);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(0x4, digest);
        bytes memory signature = abi.encodePacked(r, s, v);

        // Player B accepts
        vm.startPrank(playerB);
        vm.deal(playerB, 1 ether);
        duel.playerBAccept{ value: 1 ether }(playerB, nonce, signature); // Passing playerB as payout address
        vm.stopPrank();

        // Duel should be active now and playerB accepted
        assertTrue(duel.playerBAccepted());
        assertFalse(duel.duelExpiredOrFinished());

        // Warp to decision period
        uint256 creationTime = duel.creationTime();
        uint256 decisionLockDurationValue = duel.decisionLockDuration();

        uint256 decisionStartTime = creationTime + decisionLockDurationValue;

        vm.warp(decisionStartTime + 1);

        // Players agree on the winner (Option A)
        vm.startPrank(playerA);
        duel.playersAgree(duel.optionA());
        vm.stopPrank();

        vm.startPrank(playerB);
        duel.playersAgree(duel.optionA());
        vm.stopPrank();

        // Check that duelExpiredOrFinished is true
        assertTrue(duel.duelExpiredOrFinished());
        assertTrue(duel.decisionMade());

        nonce++;
    }

    function testUpdateStatusToExpired() public {
        // Warp to after funding duration
        uint256 creationTime = duel.creationTime();
        uint256 fundingDurationValue = duel.fundingDuration();

        vm.warp(creationTime + fundingDurationValue + 1);

        // Update status
        duel.updateStatus();

        // Check that duelExpiredOrFinished is true
        assertTrue(duel.duelExpiredOrFinished());
    }
}
