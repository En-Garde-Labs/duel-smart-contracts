// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {HelperConfig} from "./HelperConfig.sol";
import {Duel} from "../src/Duel.sol";
import {DuelFactory} from "../src/DuelFactory.sol";

contract Deploy is Script {
    HelperConfig helperConfig;

    address public duelWallet;
    uint256 public duelFee;
    uint256 public fundingTimeLimit;
    uint256 public decidingTimeLimit;

    function run() public {
        Duel duel = deployDuelImplementation();
        DuelFactory factory = deployDuelFactory(address(duel));
        console.log("Duel implementation deployed at: ", address(duel));
        console.log("Duel factory deployed at: ", address(factory));
    }

    function deployDuelImplementation() public returns (Duel) {
        helperConfig = new HelperConfig();
        HelperConfig.NetworkConfig memory config = helperConfig.getConfig();
        vm.startBroadcast(config.account);
        Duel duel = new Duel();
        vm.stopBroadcast();
        return duel;
    }

    function deployDuelFactory(
        address _duelImplementation
    ) public returns (DuelFactory) {
        helperConfig = new HelperConfig();
        HelperConfig.NetworkConfig memory config = helperConfig.getConfig();

        vm.startBroadcast(config.account);
        DuelFactory duelFactory = new DuelFactory(
            _duelImplementation,
            duelWallet,
            duelFee,
            fundingTimeLimit,
            decidingTimeLimit
        );
        vm.stopBroadcast();
        return duelFactory;
    }
}
