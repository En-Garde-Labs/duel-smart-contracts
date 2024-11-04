// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {IDuel} from "./Duel.sol";
import {DuelSide} from "./DuelSide.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";

error DuelFactory__InvalidFundingTime();
error DuelFactory__InvalidDecidingTime();
error DuelFactory__InvalidAmount();
error DuelFactory__InvalidETHValue();
error DuelFactory__InvalidImplementation();

contract DuelFactory is Ownable {
    uint256 private _nextDuelId;
    address public duelImplementation;
    address public duelWallet;
    uint256 public duelFee;
    uint256 public fundingTimeLimit;
    uint256 public decidingTimeLimit;

    event NewImplementation(address indexed newImplementation);
    event DuelCreated(uint256 indexed tokenId, address indexed duel);
    event NewFee(uint256 indexed newFee);
    event NewDuelWallet(address newWallet);
    event NewFundingTimeLimit(uint256 newLimit);
    event NewDecidingTimeLimit(uint256 newLimit);

    constructor(
        address _duelImplementation,
        address _duelWallet,
        uint256 _duelFee,
        uint256 _fundingTimeLimit,
        uint256 _decidingTimeLimit
    ) Ownable(msg.sender) {
        duelImplementation = _duelImplementation;
        duelWallet = _duelWallet;
        duelFee = _duelFee;
        fundingTimeLimit = _fundingTimeLimit;
        decidingTimeLimit = _decidingTimeLimit;
    }

    // createDuel's caller is PLAYER A
    function createDuel(
        string memory _title,
        string memory _optionADescription,
        string memory _optionBDescription,
        address _payoutA,
        address _playerB,
        uint256 _amount,
        uint256 _fundingTime,
        uint256 _decidingTime,
        address _judge
    ) public payable {
        if (_fundingTime > fundingTimeLimit)
            revert DuelFactory__InvalidFundingTime();
        if (_decidingTime > decidingTimeLimit)
            revert DuelFactory__InvalidDecidingTime();
        if (_amount == 0) revert DuelFactory__InvalidAmount();
        if (msg.value == 0 || msg.value > _amount)
            revert DuelFactory__InvalidETHValue();
        uint256 duelId = _nextDuelId++;
        ERC1967Proxy proxy = new ERC1967Proxy(
            duelImplementation,
            abi.encodeWithSignature(
                "initialize(uint256,address,address,string,string,string,address,address,address,uint256,uint256,address)",
                abi.encodePacked(
                    duelId,
                    address(this),
                    duelWallet,
                    _title, // duel's title
                    _optionADescription, // duel's option A
                    _optionBDescription, // duel's option B
                    _payoutA, // payout wallet for option A
                    msg.sender, // player A
                    _playerB,
                    _fundingTime, // funding time limit
                    _decidingTime, // deciding time limit
                    _judge // judge address
                )
            )
        );
        // duelSideA contract must be funded with value > 0
        DuelSide duelSideA = new DuelSide{value: msg.value}(
            address(proxy),
            _optionADescription,
            _amount,
            _fundingTime
        );
        DuelSide duelSideB = new DuelSide(
            address(proxy),
            _optionBDescription,
            _amount,
            _fundingTime
        );

        IDuel(address(proxy)).setOptionsAddresses(
            address(duelSideA),
            address(duelSideB)
        );

        emit DuelCreated(duelId, address(proxy));
    }

    function setImplementation(address _newImplementation) public onlyOwner {
        if (_newImplementation.code.length == 0)
            revert DuelFactory__InvalidImplementation();
        duelImplementation = _newImplementation;
        emit NewImplementation(_newImplementation);
    }

    function setDuelWallet(address _newWallet) public onlyOwner {
        duelWallet = _newWallet;
        emit NewDuelWallet(_newWallet);
    }

    function setFee(uint256 _newFee) public onlyOwner {
        duelFee = _newFee;
        emit NewFee(_newFee);
    }

    function setFundingTimeLimit(uint256 _newLimit) public onlyOwner {
        // if(_newLimit < 3600 (1 hour)) revert with error message
        fundingTimeLimit = _newLimit;
        emit NewFundingTimeLimit(_newLimit);
    }

    function setDecidingTimeLimit(uint256 _newLimit) public onlyOwner {
        decidingTimeLimit = _newLimit;
        emit NewDecidingTimeLimit(_newLimit);
    }
}
