// // SPDX-License-Identifier: MIT

// pragma solidity ^0.8.24;

// import {Test, console} from "forge-std/Test.sol";
// import {Deploy} from "script/DeployTests.s.sol";
// import {DuelFactory} from "src/DuelFactory.sol";
// import {Duel} from "src/Duel.sol";
// import {DuelSide} from "src/DuelSide.sol";
// import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

// contract DuelFactoryTest is Test {
//     // Contracts
//     DuelFactory duelFactory;
//     Duel duelImplementation;
//     address duelImplementationAddress;
//     address duelWallet = address(0xdeadbeef); // Example duel wallet

//     // Users
//     address owner = address(this);
//     address playerA = address(0x1);
//     address playerB = address(0x2);
//     address judge = address(0x3);

//     // Test variables
//     uint256 duelFee = 2; // 2%
//     uint256 fundingTimeLimit = 1 weeks;
//     uint256 decidingTimeLimit = 1 weeks;

//     function setUp() public {
//         // Deploy the Duel implementation contract
//         duelImplementation = new Duel();
//         duelImplementationAddress = address(duelImplementation);

//         // Deploy the DuelFactory contract
//         duelFactory = new DuelFactory(
//             duelImplementationAddress,
//             duelWallet,
//             duelFee,
//             fundingTimeLimit,
//             decidingTimeLimit
//         );
//     }

//     function testDeployment() public {
//         assertEq(duelFactory.duelImplementation(), duelImplementationAddress);
//         assertEq(duelFactory.duelWallet(), duelWallet);
//         assertEq(duelFactory.duelFee(), duelFee);
//         assertEq(duelFactory.fundingTimeLimit(), fundingTimeLimit);
//         assertEq(duelFactory.decidingTimeLimit(), decidingTimeLimit);
//     }

//     function testCreateDuel() public {
//         // Prepare inputs
//         string memory title = "Test Duel";
//         string memory optionADescription = "Option A";
//         string memory optionBDescription = "Option B";
//         address payoutA = address(0x4);
//         uint256 amount = 1 ether;
//         uint256 fundingTime = 3 days;
//         uint256 decidingTime = 2 days;

//         // Start impersonating playerA
//         vm.startPrank(playerA);

//         // Call createDuel with valid inputs
//         vm.deal(playerA, amount);
//         vm.expectEmit(true, true, false, false);
//         emit DuelCreated(0, address(0)); // We don't know the duel address yet

//         duelFactory.createDuel{value: amount}(
//             title,
//             optionADescription,
//             optionBDescription,
//             payoutA,
//             playerB,
//             amount,
//             fundingTime,
//             decidingTime,
//             judge
//         );

//         // Stop impersonation
//         vm.stopPrank();
//     }

//     function testCreateDuelInvalidPlayerB() public {
//         // Prepare inputs where playerB is the same as playerA
//         string memory title = "Test Duel";
//         string memory optionADescription = "Option A";
//         string memory optionBDescription = "Option B";
//         address payoutA = address(0x4);
//         uint256 amount = 1 ether;
//         uint256 fundingTime = 3 days;
//         uint256 decidingTime = 2 days;

//         // Start impersonating playerA
//         vm.startPrank(playerA);

//         // Expect revert
//         vm.expectRevert(DuelFactory__InvalidPlayerB.selector);

//         duelFactory.createDuel{value: amount}(
//             title,
//             optionADescription,
//             optionBDescription,
//             payoutA,
//             playerA, // Invalid: playerB is the same as playerA
//             amount,
//             fundingTime,
//             decidingTime,
//             judge
//         );

//         vm.stopPrank();
//     }

//     function testCreateDuelInvalidFundingTime() public {
//         // Prepare inputs with fundingTime exceeding the limit
//         string memory title = "Test Duel";
//         string memory optionADescription = "Option A";
//         string memory optionBDescription = "Option B";
//         address payoutA = address(0x4);
//         uint256 amount = 1 ether;
//         uint256 fundingTime = fundingTimeLimit + 1 days; // Exceeds limit
//         uint256 decidingTime = 2 days;

//         // Start impersonating playerA
//         vm.startPrank(playerA);

//         // Expect revert
//         vm.expectRevert(DuelFactory__InvalidFundingTime.selector);

//         duelFactory.createDuel{value: amount}(
//             title,
//             optionADescription,
//             optionBDescription,
//             payoutA,
//             playerB,
//             amount,
//             fundingTime,
//             decidingTime,
//             judge
//         );

//         vm.stopPrank();
//     }

//     function testSetImplementation() public {
//         address newImplementation = address(new Duel());

//         // Only owner can call
//         vm.prank(owner);
//         duelFactory.setImplementation(newImplementation);
//         assertEq(duelFactory.duelImplementation(), newImplementation);

//         // Non-owner cannot call
//         vm.prank(playerA);
//         vm.expectRevert("Ownable: caller is not the owner");
//         duelFactory.setImplementation(newImplementation);
//     }

//     function testPauseUnpause() public {
//         // Only owner can call pause
//         vm.prank(playerA);
//         vm.expectRevert("Ownable: caller is not the owner");
//         duelFactory.pause();

//         vm.prank(owner);
//         duelFactory.pause();
//         assertTrue(duelFactory.paused());

//         // Cannot create duel when paused
//         vm.prank(playerA);
//         vm.expectRevert("Pausable: paused");
//         duelFactory.createDuel(
//             "Test",
//             "Option A",
//             "Option B",
//             address(0x0),
//             playerB,
//             1 ether,
//             1 days,
//             1 days,
//             judge
//         );

//         // Only owner can call unpause
//         vm.prank(playerA);
//         vm.expectRevert("Ownable: caller is not the owner");
//         duelFactory.unpause();

//         vm.prank(owner);
//         duelFactory.unpause();
//         assertFalse(duelFactory.paused());
//     }

//     function testCreateDuelEmitsEvent() public {
//         string memory title = "Test Duel";
//         string memory optionADescription = "Option A";
//         string memory optionBDescription = "Option B";
//         address payoutA = address(0x4);
//         uint256 amount = 1 ether;
//         uint256 fundingTime = 3 days;
//         uint256 decidingTime = 2 days;

//         // Start impersonating playerA
//         vm.startPrank(playerA);

//         vm.deal(playerA, amount);

//         // Capture the DuelCreated event
//         vm.recordLogs();

//         duelFactory.createDuel{value: amount}(
//             title,
//             optionADescription,
//             optionBDescription,
//             payoutA,
//             playerB,
//             amount,
//             fundingTime,
//             decidingTime,
//             judge
//         );

//         Vm.Log[] memory entries = vm.getRecordedLogs();

//         // Find the DuelCreated event
//         bytes32 eventSignature = keccak256("DuelCreated(uint256,address)");
//         bool eventFound = false;
//         uint256 duelId;
//         address duelAddress;

//         for (uint256 i = 0; i < entries.length; i++) {
//             if (entries[i].topics[0] == eventSignature) {
//                 duelId = uint256(entries[i].topics[1]);
//                 duelAddress = address(uint160(uint256(entries[i].topics[2])));
//                 eventFound = true;
//                 break;
//             }
//         }

//         require(eventFound, "DuelCreated event not found");
//         assertEq(duelId, 0); // First duel, so ID should be 0
//         assertTrue(duelAddress != address(0));

//         vm.stopPrank();
//     }

//     function testCreateDuelContractsDeployed() public {
//         // Prepare inputs
//         string memory title = "Test Duel";
//         string memory optionADescription = "Option A";
//         string memory optionBDescription = "Option B";
//         address payoutA = address(0x4);
//         uint256 amount = 1 ether;
//         uint256 fundingTime = 3 days;
//         uint256 decidingTime = 2 days;

//         // Start impersonating playerA
//         vm.startPrank(playerA);

//         vm.deal(playerA, amount);

//         // Capture the DuelCreated event
//         vm.recordLogs();

//         duelFactory.createDuel{value: amount}(
//             title,
//             optionADescription,
//             optionBDescription,
//             payoutA,
//             playerB,
//             amount,
//             fundingTime,
//             decidingTime,
//             judge
//         );

//         Vm.Log[] memory entries = vm.getRecordedLogs();

//         // Find the DuelCreated event
//         bytes32 eventSignature = keccak256("DuelCreated(uint256,address)");
//         address duelAddress;

//         for (uint256 i = 0; i < entries.length; i++) {
//             if (entries[i].topics[0] == eventSignature) {
//                 duelAddress = address(uint160(uint256(entries[i].topics[2])));
//                 break;
//             }
//         }

//         require(duelAddress != address(0), "Duel contract not deployed");

//         // Interact with the Duel contract
//         Duel duel = Duel(duelAddress);

//         // Check that the Duel contract has the correct values
//         assertEq(duel.title(), title);
//         assertEq(duel.playerA(), playerA);
//         assertEq(duel.playerB(), playerB);
//         assertEq(duel.duelWallet(), duelWallet);
//         assertEq(duel.factory(), address(duelFactory));
//         assertEq(duel.judge(), judge);

//         // Verify DuelSide contracts
//         address optionAAddress = duel.optionA();
//         address optionBAddress = duel.optionB();

//         assertTrue(optionAAddress != address(0), "Option A not set");
//         assertTrue(optionBAddress != address(0), "Option B not set");

//         // Check that the funds were sent to DuelSide A
//         uint256 balanceOptionA = optionAAddress.balance;
//         assertEq(balanceOptionA, amount, "Funds not sent to Option A");

//         vm.stopPrank();
//     }
// }
