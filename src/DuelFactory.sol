// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {Duel} from "./Duel.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract DuelFactory is Ownable {
    uint256 private _nextTokenId;
    address public duelImplementation;

    event ImplementationSet(address indexed newImplementation);

    constructor(address _duelImplementation) Ownable(msg.sender) {
        duelImplementation = _duelImplementation;
    }

    function createDuel() public {
        uint256 tokenId = _nextTokenId++;
        ERC1967Proxy proxy = new ERC1967Proxy(duelImplementation, "");
    }

    function setImplementation(address _newImplementation) public onlyOwner {
        duelImplementation = _newImplementation;
        emit ImplementationSet(_newImplementation);
    }
}
