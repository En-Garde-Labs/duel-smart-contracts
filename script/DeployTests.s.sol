// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {HelperConfig} from "./HelperConfig.s.sol";
import {Duel} from "src/Duel.sol";
import {DuelFactory} from "src/DuelFactory.sol";

contract DeployTests is Script {
    HelperConfig helperConfig;

    address public duelWallet = makeAddr("duelWallet");
    uint256 public duelFee = 100; // 1%
    uint256 public fundingTimeLimit = 1 weeks;
    uint256 public decidingTimeLimit = 1 weeks;

    function run() public returns(Duel, DuelFactory) {
        Duel duel = deployDuelImplementation();
        DuelFactory factory = deployDuelFactory(address(duel));
        return (duel, factory);
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
            duelFee
        );
        vm.stopBroadcast();
        return duelFactory;
    }
}
