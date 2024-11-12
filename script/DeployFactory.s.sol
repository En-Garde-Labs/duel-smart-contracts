// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {Defender, DefenderOptions} from "openzeppelin-foundry-upgrades/Defender.sol";

import {DuelFactory} from "src/DuelFactory.sol";

contract DeployFactoryScript is Script {
    function setUp() public {}

    function run() public {
        // Set constructor parameters for DuelFactory
        address duelImplementation = 0x9Db0822eF59D14Dfd5Aa3B5f6C591875816cF866;
        address duelWallet = 0x7611A60c2346f3D193f65B051eD6Ae93239FF25e;
        uint256 duelFee = 100; // example fee in basis points (1%)
        address multisig = vm.envAddress("BASE_SEPOLIA_MULTISIG");
        address owner = 0x65AC8b2f35A8CE197c600C3f7375ca28074110c6;

        DefenderOptions memory opts;
        opts.salt = generateRandomSalt();
        opts.useDefenderDeploy = true;

        // Deploy DuelFactory using OpenZeppelin Defender
        address deployResponse = Defender.deployContract(
            "DuelFactory.sol",
            abi.encode(owner, duelImplementation, duelWallet, duelFee),
            opts
        );

        address factoryAddress = deployResponse;
        console.log("Deployed DuelFactory to address:", factoryAddress);
    }

    function generateRandomSalt() internal view returns (bytes32) {
        return
            keccak256(
                abi.encodePacked(block.timestamp, block.prevrandao, msg.sender)
            );
    }
}
