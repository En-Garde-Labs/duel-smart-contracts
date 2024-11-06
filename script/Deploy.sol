// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {HelperConfig} from "./HelperConfig.sol";
import {Duel} from "../src/Duel.sol";
import {DuelFactory} from "../src/DuelFactory.sol";

contract Deploy is Script {

    HelperConfig helperConfig;
    function run() public {
        
    }

    function deployDuelImplementation() public returns(Duel){
        helperConfig = new HelperConfig();
        HelperConfig.NetworkConfig memory config = helperConfig.getConfig();

        vm.startBroadcast(config.account);
        Duel duel = new Duel();
        vm.stopBroadcast();
        return duel;
    }

    function deployDuelFactory() public {
        // Deploy DuelFactory.sol
    }
}