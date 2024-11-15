// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {Defender, DefenderOptions} from "openzeppelin-foundry-upgrades/Defender.sol";
import {Duel} from "src/Duel.sol";

contract DeployFactoryScript is Script {
    function setUp() public {}

    function run() public {
        DefenderOptions memory opts;
        opts.salt = generateRandomSalt();
        opts.useDefenderDeploy = true;

        // Deploy Duel using OpenZeppelin Defender
        address deployResponse = Defender.deployContract("Duel.sol", "", opts);

        address duelAddress = deployResponse;
        console.log("Deployed Duel Implementation to address:", duelAddress);
    }

    function generateRandomSalt() internal view returns (bytes32) {
        return
            keccak256(
                abi.encodePacked(block.timestamp, block.prevrandao, msg.sender)
            );
    }
}
