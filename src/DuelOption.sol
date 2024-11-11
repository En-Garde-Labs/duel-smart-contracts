// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {IDuel} from "./Duel.sol";

error DuelOption__Unauthorized();
error DuelOption__PayoutFailed();
error DuelOption__AmountExceeded();
error DuelOption__FundingTimeEnded();
error DuelOption__DuelNotExpired();
error DuelOption__BalanceIsZero();

contract DuelOption {
    uint256 public amount;
    uint256 public creationTime;
    uint256 public fundingTime;
    uint256 public duelFee; // Fee in basis points. E.g., 'duelFee = 125' -> 1.25%
    address public duelAddress;

    mapping(address user => uint256 balance) public balances;

    event PayoutSent(address indexed payoutAddress, uint256 indexed amount);
    event FundsClaimed(address indexed user, uint256 indexed amount);

    constructor(
        address _duelAddress,
        uint256 _amount,
        uint256 _fundingTime,
        uint256 _duelFee,
        address _initialFunder
    ) payable {
        duelAddress = _duelAddress;
        amount = _amount;
        creationTime = block.timestamp;
        fundingTime = _fundingTime;
        duelFee = _duelFee;
        if (msg.value > 0) {
            balances[_initialFunder] = msg.value;
        }
    }

    receive() external payable {
        if (address(this).balance > amount) revert DuelOption__AmountExceeded();
        if (block.timestamp > creationTime + fundingTime)
            revert DuelOption__FundingTimeEnded();
        balances[msg.sender] += msg.value;
    }

    function sendPayout(
        address payable _payoutAddress,
        address _duelWallet
    ) external returns (bool) {
        if (msg.sender != duelAddress) revert DuelOption__Unauthorized();
        uint256 _duelFee = (address(this).balance * duelFee) / 10000;
        uint256 _payoutAmount = address(this).balance - _duelFee;
        (bool payoutSuccess, ) = _payoutAddress.call{value: _payoutAmount}("");
        (bool feeSuccess, ) = payable(_duelWallet).call{value: _duelFee}("");
        if (!payoutSuccess || !feeSuccess) revert DuelOption__PayoutFailed();
        emit PayoutSent(_payoutAddress, address(this).balance);
        return true;
    }

    function claimFunds() public {
        // Request status update from Duel contract
        IDuel duel = IDuel(duelAddress);
        duel.updateStatus();

        if (!duel.duelExpiredOrFinished()) {
            revert DuelOption__DuelNotExpired();
        }
        uint256 _amount = balances[msg.sender];
        if (_amount == 0) revert DuelOption__BalanceIsZero();
        balances[msg.sender] = 0;
        (bool success, ) = msg.sender.call{value: _amount}("");
        if (!success) revert DuelOption__PayoutFailed();
        emit FundsClaimed(msg.sender, _amount);
    }
}
