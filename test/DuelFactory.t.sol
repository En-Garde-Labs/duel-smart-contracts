// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {Test, console, Vm} from "forge-std/Test.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";
import {DeployTests} from "script/DeployTests.s.sol";
import {DuelFactory} from "src/DuelFactory.sol";
import {Duel} from "src/Duel.sol";
import {DuelOption} from "src/DuelOption.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract DuelFactoryTest is Test {
    // Config contracts
    HelperConfig helperConfig;
    HelperConfig.NetworkConfig config;
    DeployTests deploy;

    // Errors
    error DuelFactory__InvalidDurations();
    error DuelFactory__InvalidAmount();
    error DuelFactory__InvalidETHValue();
    error DuelFactory__InvalidImplementation();
    error DuelFactory__InvalidPlayer();
    error DuelFactory__InvalidFee();

    // Events
    event DuelCreated(uint256 indexed duelId, address indexed duelAddress);

    // Contracts
    DuelFactory duelFactory;
    Duel duelImplementation;
    address duelImplementationAddress;
    address duelWallet = makeAddr("duelWallet");

    // Users
    address owner;
    address playerA = address(0x1);
    address playerB = address(0x2);
    address judge = address(0x3);

    // Test variables
    uint256 duelFee = 100; // 1%

    function setUp() public {
        helperConfig = new HelperConfig();
        config = helperConfig.getConfig();
        deploy = new DeployTests();
        (duelImplementation, duelFactory) = deploy.run();

        duelImplementationAddress = address(duelImplementation);
        owner = config.account;
    }

    function testDeployment() public view {
        assertEq(duelFactory.duelImplementation(), duelImplementationAddress);
        assertEq(duelFactory.duelWallet(), duelWallet);
        assertEq(duelFactory.duelFee(), duelFee);
    }

    function testCreateDuel() public {
        string memory title = "Test Duel";
        address payoutA = address(0x4);
        uint256 amount = 1 ether;
        uint256 fundingDuration = 3 days;
        uint256 decisionLockDuration = 5 days;

        vm.deal(playerA, amount);
        vm.startPrank(playerA);

        vm.expectEmit(true, false, false, false);
        emit DuelCreated(0, address(0));

        duelFactory.createDuel{value: amount}(
            title,
            payoutA,
            playerB,
            amount,
            fundingDuration,
            decisionLockDuration,
            judge
        );

        vm.stopPrank();
    }

    function testCreateDuelInvalidPlayerB() public {
        string memory title = "Test Duel";
        address payoutA = address(0x4);
        uint256 amount = 1 ether;
        uint256 fundingDuration = 3 days;
        uint256 decisionLockDuration = 5 days;

        vm.deal(playerA, amount);
        vm.startPrank(playerA);

        vm.expectRevert(DuelFactory__InvalidPlayer.selector);

        duelFactory.createDuel{value: amount}(
            title,
            payoutA,
            playerA, // Invalid: playerB is the same as playerA
            amount,
            fundingDuration,
            decisionLockDuration,
            judge
        );

        vm.stopPrank();
    }

    function testCreateDuelInvalidDurations() public {
        string memory title = "Test Duel";
        address payoutA = address(0x4);
        uint256 amount = 1 ether;
        uint256 fundingDuration = 5 days;
        uint256 decisionLockDuration = 3 days; // Invalid: decisionLockDuration <= fundingDuration

        vm.deal(playerA, amount);
        vm.startPrank(playerA);

        vm.expectRevert(DuelFactory__InvalidDurations.selector);

        duelFactory.createDuel{value: amount}(
            title,
            payoutA,
            playerB,
            amount,
            fundingDuration,
            decisionLockDuration,
            judge
        );

        vm.stopPrank();
    }

    function testSetImplementation() public {
        address newImplementation = address(new Duel());

        // Only owner can call
        vm.prank(config.account);
        duelFactory.setImplementation(newImplementation);
        assertEq(duelFactory.duelImplementation(), newImplementation);

        // Non-owner cannot call
        vm.prank(playerA);
        vm.expectRevert();
        duelFactory.setImplementation(newImplementation);
    }

    function testPauseUnpause() public {
        // Only owner can call pause
        vm.prank(playerA);
        vm.expectRevert();
        duelFactory.pause();


        vm.prank(config.account);
        duelFactory.pause();
        assertTrue(duelFactory.paused());

        // Cannot create duel when paused
        vm.deal(playerA, 1 ether);
        vm.prank(playerA);
        vm.expectRevert();
        duelFactory.createDuel{value: 1 ether}(
            "Test",
            address(0x0),
            playerB,
            1 ether,
            1 days,
            2 days,
            judge
        );

        // Only owner can call unpause
        vm.prank(playerA);
        vm.expectRevert();
        duelFactory.unpause();

        vm.prank(config.account);
        duelFactory.unpause();
        assertFalse(duelFactory.paused());
    }

    function testCreateDuelEmitsEvent() public {
        string memory title = "Test Duel";
        address payoutA = address(0x4);
        uint256 amount = 1 ether;
        uint256 fundingDuration = 3 days;
        uint256 decisionLockDuration = 5 days;

        vm.deal(playerA, amount);
        vm.startPrank(playerA);

        vm.recordLogs();

        duelFactory.createDuel{value: amount}(
            title,
            payoutA,
            playerB,
            amount,
            fundingDuration,
            decisionLockDuration,
            judge
        );

        Vm.Log[] memory entries = vm.getRecordedLogs();

        bytes32 eventSignature = keccak256("DuelCreated(uint256,address)");
        bool eventFound = false;
        uint256 duelId;
        address duelAddress;

        for (uint256 i = 0; i < entries.length; i++) {
            if (entries[i].topics[0] == eventSignature) {
                duelId = uint256(entries[i].topics[1]);
                duelAddress = address(uint160(uint256(entries[i].topics[2])));
                eventFound = true;
                break;
            }
        }

        require(eventFound, "DuelCreated event not found");
        assertEq(duelId, 0); // First duel, so ID should be 0
        assertTrue(duelAddress != address(0));

        vm.stopPrank();
    }

    function testCreateDuelContractsDeployed() public {
        string memory title = "Test Duel";
        address payoutA = address(0x4);
        uint256 amount = 1 ether;
        uint256 fundingDuration = 3 days;
        uint256 decisionLockDuration = 5 days;

        vm.deal(playerA, amount);
        vm.startPrank(playerA);

        vm.recordLogs();

        duelFactory.createDuel{value: amount}(
            title,
            payoutA,
            playerB,
            amount,
            fundingDuration,
            decisionLockDuration,
            judge
        );

        Vm.Log[] memory entries = vm.getRecordedLogs();

        bytes32 eventSignature = keccak256("DuelCreated(uint256,address)");
        address duelAddress;

        for (uint256 i = 0; i < entries.length; i++) {
            if (entries[i].topics[0] == eventSignature) {
                duelAddress = address(uint160(uint256(entries[i].topics[2])));
                break;
            }
        }

        require(duelAddress != address(0), "Duel contract not deployed");

        // Interact with the Duel contract
        Duel duel = Duel(duelAddress);

        // Check that the Duel contract has the correct values
        assertEq(duel.title(), title);
        assertEq(duel.playerA(), playerA);
        assertEq(duel.playerB(), playerB);
        assertEq(duel.duelWallet(), duelWallet);
        assertEq(duel.factory(), address(duelFactory));
        assertEq(duel.judge(), judge);

        // Verify DuelOption contracts
        address optionAAddress = duel.optionA();
        address optionBAddress = duel.optionB();

        assertTrue(optionAAddress != address(0), "Option A not set");
        assertTrue(optionBAddress != address(0), "Option B not set");

        // Check that the funds were sent to DuelOption A
        uint256 balanceOptionA = optionAAddress.balance;
        assertEq(balanceOptionA, amount, "Funds not sent to Option A");

        vm.stopPrank();
    }
}