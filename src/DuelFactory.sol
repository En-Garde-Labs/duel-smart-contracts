// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {IDuel} from "./Duel.sol";
import {DuelOption} from "./DuelOption.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";

error DuelFactory__InvalidDurations();
error DuelFactory__InvalidAmount();
error DuelFactory__InvalidETHValue();
error DuelFactory__InvalidImplementation();
error DuelFactory__InvalidPlayerB();
error DuelFactory__InvalidFee();

contract DuelFactory is Ownable, Pausable {
    
    uint256 private _nextDuelId;
    uint256 public duelFee; // Fee in basis points. E.g., 'duelFee = 125' -> 1.25%
    address public duelImplementation;
    address public duelWallet;

    event NewImplementation(address indexed newImplementation);
    event DuelCreated(uint256 indexed tokenId, address indexed duel);
    event NewFee(uint256 indexed newFee);
    event NewDuelWallet(address indexed newWallet);

    constructor(
        address _duelImplementation,
        address _duelWallet,
        uint256 _duelFee
    ) Ownable(msg.sender) {
        if (_duelFee > 10000) revert DuelFactory__InvalidFee(); // Max 100% in basis points
        duelImplementation = _duelImplementation;
        duelWallet = _duelWallet;
        duelFee = _duelFee;
    }

    function createDuel(
        string memory _title,
        address _payoutA,
        address _playerB,
        uint256 _amount,
        uint256 _fundingDuration,
        uint256 _decisionLockDuration,
        address _judge
    ) external payable whenNotPaused returns (address) {
        // check a min/max duration for fundingDuration?
        // check a min/max duration for decisionLockDuration?
        if (_playerB == msg.sender || _playerB == address(0))
            revert DuelFactory__InvalidPlayerB();
        if (_amount == 0) revert DuelFactory__InvalidAmount();
        if (msg.value == 0 || msg.value > _amount)
            revert DuelFactory__InvalidETHValue();
        if (_decisionLockDuration <= _fundingDuration)
            revert DuelFactory__InvalidDurations();
        uint256 duelId = _nextDuelId++;
        ERC1967Proxy proxy = new ERC1967Proxy(
            duelImplementation,
            abi.encodeWithSignature(
                "initialize(uint256,address,address,string,uint256,address,address,address,uint256,uint256,address)",
                duelId,
                address(this),
                duelWallet,
                _title, // duel's title
                _amount, // amount of the duel
                _payoutA, // payout wallet for option A
                msg.sender, // player A
                _playerB,
                _fundingDuration, // funding time limit
                _decisionLockDuration, // deciding time starts
                _judge // judge address
            )
        );

        DuelOption DuelOptionA = new DuelOption{value: msg.value}(
            address(proxy),
            _amount,
            _fundingDuration,
            duelFee,
            msg.sender
        );
        DuelOption DuelOptionB = new DuelOption(
            address(proxy),
            _amount,
            _fundingDuration,
            duelFee,
            address(0) // No initial funder
        );

        IDuel(address(proxy)).setOptionsAddresses(
            address(DuelOptionA),
            address(DuelOptionB)
        );

        emit DuelCreated(duelId, address(proxy));
        return address(proxy);
    }

    function setImplementation(address _newImplementation) external onlyOwner {
        if (_newImplementation.code.length == 0)
            revert DuelFactory__InvalidImplementation();
        duelImplementation = _newImplementation;
        emit NewImplementation(_newImplementation);
    }

    function setDuelWallet(address _newWallet) external onlyOwner {
        duelWallet = _newWallet;
        emit NewDuelWallet(_newWallet);
    }

    function setFee(uint256 _newFee) external onlyOwner {
        if (_newFee > 10000) revert DuelFactory__InvalidFee(); // Max 100% in basis points
        duelFee = _newFee;
        emit NewFee(_newFee);
    }

    function pause() external onlyOwner whenNotPaused {
        _pause();
    }

    function unpause() external onlyOwner whenPaused {
        _unpause();
    }
}
