// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {Deploy} from "../script/DeployTests.s.sol";
import {DuelFactory} from "../src/DuelFactory.sol";

contract FactoryTests is Test {
  function setUp () public {
    console.log("Setting up FactoryTests");
  }
}