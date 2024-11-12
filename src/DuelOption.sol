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
    uint256 public fundingDuration;
    uint256 public duelFee; // Fee in basis points. E.g., 'duelFee = 125' -> 1.25%
    address public duelAddress;

    mapping(address user => uint256 balance) public balances;

    event PayoutSent(address indexed payoutAddress, uint256 indexed amount);
    event FundsClaimed(address indexed user, uint256 indexed amount);

    /**
     * @notice Constructor for the `DuelOption` contract, which manages funding and payouts for a duel option.
     * @param _duelAddress Address of the associated `Duel` contract.
     * @param _amount The target amount of funding for this option in wei.
     * @param _fundingTime The duration in seconds for which funding is open.
     * @param _duelFee Fee percentage in basis points (e.g., 125 for 1.25%).
     * @param _initialFunder Address of the initial funder, if any, for setting initial balances.
     */
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
        fundingDuration = _fundingTime;
        duelFee = _duelFee;
        if (msg.value > 0) {
            balances[_initialFunder] = msg.value;
        }
    }

    /**
     * @notice Receives additional funding for the option, up to the target amount.
     * @dev Adds the sender’s contribution to their balance if within the funding period.
     * @custom:reverts DuelOption__AmountExceeded if the target amount is exceeded.
     * @custom:reverts DuelOption__FundingTimeEnded if the funding time has expired.
     */
    receive() external payable {
        if (address(this).balance > amount) revert DuelOption__AmountExceeded();
        if (block.timestamp > creationTime + fundingDuration)
            revert DuelOption__FundingTimeEnded();
        balances[msg.sender] += msg.value;
    }

    /**
     * @notice Sends payout to the winning player and fee to the duel wallet after a decision is made.
     * @dev Only callable by the associated `Duel` contract.
     * @param _payoutAddress The address where the payout will be sent.
     * @param _duelWallet The address where the fee will be sent.
     * @return success Boolean indicating successful payout.
     * @custom:reverts DuelOption__Unauthorized if called by any address other than the `Duel` contract.
     * @custom:reverts DuelOption__PayoutFailed if the payout or fee transfer fails.
     */
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

    /**
     * @notice Allows a funder to claim their funds if the duel expires without a decision.
     * @dev Calls `updateStatus` on the associated `Duel` contract to check for expiration status.
     * @custom:reverts DuelOption__DuelNotExpired if the duel is not marked as expired or finished.
     * @custom:reverts DuelOption__BalanceIsZero if the caller has no funds to claim.
     */
    function claimFunds() external {
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
