// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {Defender, DefenderOptions} from "openzeppelin-foundry-upgrades/Defender.sol";

import {DuelFactory} from "src/DuelFactory.sol";

contract DeployFactoryScript is Script {
    function setUp() public {}

    function run() public {
        // Set constructor parameters for DuelFactory
        address duelImplementation = 0xC42c74D173a1d8a655f5f310e29bcCD819284d1e;
        address duelWallet = 0x60f2A726977b1199fAdc6FB38d600a1b277Dfd74;
        uint256 duelFee = 100; // example fee in basis points (1%)

        DefenderOptions memory opts;
        opts.salt = "0x1234";
        opts.useDefenderDeploy = true;

        // Deploy DuelFactory using OpenZeppelin Defender
        address deployResponse = Defender.deployContract(
            "DuelFactory.sol",
            abi.encode(duelImplementation, duelWallet, duelFee),
            opts
        );

        address factoryAddress = deployResponse;
        console.log("Deployed DuelFactory to address:", factoryAddress);
    }
}
