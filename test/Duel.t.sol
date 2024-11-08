// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console, Vm} from "forge-std/Test.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";
import {DeployTests} from "script/DeployTests.s.sol";
import {DuelFactory} from "../src/DuelFactory.sol";
import {Duel} from "../src/Duel.sol";
import {DuelSide} from "../src/DuelSide.sol";
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
    error DuelImplementation__FundingTimeExceeded();
    error DuelImplementation__AlreadyAccepted();
    error DuelImplementation__NotDecidingTime();
    error DuelImplementation__InvalidETHValue();
    error DuelImplementation__FundingFailed();
    error DuelImplementation__InvalidWinner();
    error DuelImplementation__PayoutFailed();
    error DuelImplementation__DuelExpired();
    error DuelImplementation__NoJudge();
    error DuelImplementation__Unauthorized();

    // Events
    event NewDuelWallet(address indexed newWallet);
    event ParticipantAccepted(address indexed participant);
    event PayoutAddressSet(
        address indexed player,
        address indexed payoutAddress
    );
    event DuelCompleted(address indexed winner);
    event DuelExpired();

    // Contracts
    DuelFactory duelFactory;
    Duel duelImplementation;
    Duel duel;
    Duel duelWithJudge;
    Duel duelNoJudge;
    address duelImplementationAddress;
    address duelWallet = 0x7611A60c2346f3D193f65B051eD6Ae93239FF25e;

    // Users
    address playerA = address(0x1);
    address playerB = address(0x2);
    address judge = address(0x3);

    // Test variables
    uint256 duelFee = 100; // Fee in basis points (1%)
    uint256 fundingTimeLimit = 1 weeks;
    uint256 decidingTimeLimit = 1 weeks;
    uint256 fundingTime = 3 days;
    uint256 decidingTime = 2 days;

    function setUp() public {
        
        helperConfig = new HelperConfig();
        config = helperConfig.getConfig();
        deploy = new DeployTests();
        (duelImplementation, duelFactory) = deploy.run();

        duelImplementationAddress = address(duelImplementation);

        // Deploy a new Duel instance via proxy
        bytes memory data = abi.encodeWithSignature(
            "initialize(uint256,address,address,string,address,address,address,uint256,uint256,address)",
            1, // duelId
            address(duelFactory), // factory
            duelWallet, // duelWallet
            "Test Duel", // title
            playerA, // payoutA
            playerA, // playerA
            playerB, // playerB
            fundingTime, // fundingTime
            decidingTime, // decidingTime
            judge // judge
        );
        ERC1967Proxy proxy = new ERC1967Proxy(duelImplementationAddress, data);
        duel = Duel(address(proxy));

        // Deploy DuelSide contracts for options A and B
        DuelSide duelSideA = new DuelSide(
            address(duel),
            1 ether, // amount
            block.timestamp,
            fundingTime,
            duelFee
        );
        DuelSide duelSideB = new DuelSide(
            address(duel),
            1 ether, // amount
            block.timestamp,
            fundingTime,
            duelFee
        );

        // Set options addresses
        vm.prank(address(duelFactory));
        duel.setOptionsAddresses(address(duelSideA), address(duelSideB));
    }

    function createDuelWithJudge(address player) public returns(address) {
        // Provide ETH to player
        vm.deal(player, 1 ether);
        vm.startPrank(player);

        // Player creates a duel
        address duelWithJudge = duelFactory.createDuel{value: 1 ether}(
            "Test Duel",
            playerA,
            playerB,
            1 ether,
            fundingTime,
            decidingTime,
            judge
        );
        vm.stopPrank();

        return duelWithJudge;
    }

    function createDuelNoJudge(address player) public returns(address) {
        // Provide ETH to player
        vm.deal(player, 1 ether);

        // Player creates a duel
        address duelNoJudge = duelFactory.createDuel{value: 1 ether}(
            "Test Duel",
            playerA,
            playerB,
            1 ether,
            fundingTime,
            decidingTime,
            address(0)
        );

        return duelNoJudge;
    }

    function testPlayerASetPayoutAddress() public {
        // Start impersonating playerA
        vm.startPrank(playerA);

        // Player A sets payout address
        duel.setPayoutAddress(playerA);

        // Check that payoutA is set correctly
        assertEq(duel.payoutA(), playerA);

        vm.stopPrank();
    }

    function testPlayerBAccept() public {
        // Start impersonating playerB
        vm.startPrank(playerB);

        // Provide ETH to playerB
        vm.deal(playerB, 1 ether);

        // Player B sets payout address
        duel.setPayoutAddress(playerB);
        assertEq(duel.payoutB(), playerB);

        // Player B accepts the duel
        vm.expectEmit(true, false, false, false);
        emit ParticipantAccepted(playerB);
        duel.playerBAccept{value: 1 ether}(playerB);

        // Check that playerBAccepted is true
        assertTrue(duel.playerBAccepted());

        vm.stopPrank();
    }

    // function testJudgeAccept() public {
    //     // Start impersonating judge
    //     vm.startPrank(judge);

    //     // Judge accepts the duel
    //     vm.expectEmit(true, false, false, false);
    //     emit ParticipantAccepted(judge);
    //     duel.judgeAccept();

    //     // Check that judgeAccepted is true
    //     assertTrue(duel.judgeAccepted());

    //     vm.stopPrank();
    // }

    function testDuelBecomesActiveAfterAcceptance() public {
        
        address duelWithJudgeAddr = createDuelWithJudge(playerA);
        Duel duelWithJudge = Duel(duelWithJudgeAddr);
        
        // Player A sets payout address
        vm.startPrank(playerA);
        duelWithJudge.setPayoutAddress(playerA);
        vm.stopPrank();

        // Player B accepts
        vm.startPrank(playerB);
        vm.deal(playerB, 1 ether);
        duelWithJudge.playerBAccept{value: 1 ether}(playerB);
        vm.stopPrank();

        // Judge accepts
        vm.startPrank(judge);
        duelWithJudge.judgeAccept();
        vm.stopPrank();

        // Check that the duel status is ACTIVE
        assertEq(duelWithJudge.getStatus(), uint8(IDuel.Status.ACTIVE));
    }

    function testJudgeDecide() public {
        // Players and judge accept to activate the duel
        testDuelBecomesActiveAfterAcceptance();

        // Warp to deciding time
        uint256 creationTime = duel.creationTime();
        uint256 fundingTimeValue = duel.fundingTime();

        vm.warp(creationTime + fundingTimeValue + 1);

        // Start impersonating judge
        vm.startPrank(judge);

        // Judge decides the winner (Option A)
        vm.expectEmit(true, false, false, false);
        emit DuelCompleted(duel.optionA());
        duel.judgeDecide(duel.optionA());

        // Check that status is COMPLETED
        assertEq(duel.getStatus(), uint8(IDuel.Status.COMPLETED));

        vm.stopPrank();
    }

    // function testPlayersAgree() public {
    //     // Deploy a new Duel instance with no judge
    //     bytes memory data = abi.encodeWithSignature(
    //         "initialize(uint256,address,address,string,address,address,address,uint256,uint256,address)",
    //         2, // duelId
    //         address(duelFactory), // factory
    //         duelWallet, // duelWallet
    //         "Test Duel No Judge", // title
    //         playerA, // payoutA
    //         playerA, // playerA
    //         playerB, // playerB
    //         fundingTime, // fundingTime
    //         decidingTime, // decidingTime
    //         address(0) // No judge
    //     );
    //     ERC1967Proxy proxy = new ERC1967Proxy(duelImplementationAddress, data);
    //     Duel noJudgeDuel = Duel(address(proxy));

    //     // Deploy DuelSide contracts
    //     DuelSide duelSideA = new DuelSide(
    //         address(noJudgeDuel),
    //         1 ether, // amount
    //         block.timestamp,
    //         fundingTime,
    //         duelFee
    //     );
    //     DuelSide duelSideB = new DuelSide(
    //         address(noJudgeDuel),
    //         1 ether, // amount
    //         block.timestamp,
    //         fundingTime,
    //         duelFee
    //     );

    //     // Set options addresses
    //     vm.prank(address(duelFactory));
    //     noJudgeDuel.setOptionsAddresses(address(duelSideA), address(duelSideB));

    //     // Players set payout addresses
    //     vm.startPrank(playerA);
    //     noJudgeDuel.setPayoutAddress(playerA);
    //     vm.stopPrank();

    //     vm.startPrank(playerB);
    //     noJudgeDuel.setPayoutAddress(playerB);
    //     vm.stopPrank();

    //     // Player B accepts
    //     vm.startPrank(playerB);
    //     vm.deal(playerB, 1 ether);
    //     noJudgeDuel.playerBAccept{value: 1 ether}(playerB);
    //     vm.stopPrank();

    //     // Duel should be active now
    //     assertEq(noJudgeDuel.getStatus(), uint8(IDuel.Status.ACTIVE));

    //     // Warp to deciding time
    //     uint256 creationTime = noJudgeDuel.creationTime();
    //     uint256 fundingTimeValue = noJudgeDuel.fundingTime();

    //     vm.warp(creationTime + fundingTimeValue + 1);

    //     // Players agree on the winner (Option A)
    //     vm.startPrank(playerA);
    //     noJudgeDuel.playersAgree(noJudgeDuel.optionA());
    //     vm.stopPrank();

    //     vm.startPrank(playerB);
    //     noJudgeDuel.playersAgree(noJudgeDuel.optionA());
    //     vm.stopPrank();

    //     // Check that status is COMPLETED
    //     assertEq(noJudgeDuel.getStatus(), uint8(IDuel.Status.COMPLETED));
    // }

    function testUpdateStatusToExpired() public {
        // Warp to after funding time
        uint256 creationTime = duel.creationTime();
        uint256 fundingTimeValue = duel.fundingTime();

        vm.warp(creationTime + fundingTimeValue + 1);

        // Update status
        duel.updateStatus();

        // Check that status is EXPIRED
        assertEq(duel.getStatus(), uint8(IDuel.Status.EXPIRED));
    }
}
