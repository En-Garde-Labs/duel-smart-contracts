// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

error DuelSide__Unauthorized();
error DuelSide__PayoutFailed();
error DuelSide__AmountExceeded();
error DuelSide__FundingTimeEnded();

contract DuelSide {
    
    uint256 public amount;
    uint256 public creationTime;
    uint256 public fundingTime;
    uint256 public duelFee; // An integer between 0 and 100
    address public duelAddress;
    string public option;

    mapping(address user => uint256 balance) public balances;

    event PayoutSent(address indexed payoutAddress, uint256 indexed amount);
    event FundsClaimed(address indexed user, uint256 indexed amount);

    constructor(
        address _duelAddress,
        string memory _option,
        uint256 _amount,
        uint256 _creationTime,
        uint256 _fundingTime,
        uint256 _duelFee
    ) payable {
        duelAddress = _duelAddress;
        amount = _amount;
        creationTime = _creationTime;
        fundingTime = _fundingTime;
        option = _option;
        duelFee = _duelFee;
    }

    receive() external payable {
      if(address(this).balance > amount) revert DuelSide__AmountExceeded();
      if(block.timestamp > creationTime + fundingTime) revert DuelSide__FundingTimeEnded();
      balances[msg.sender] += msg.value;
    }

    function sendPayout(
        address payable _payoutAddress,
        address _duelWallet
    ) public {
        if (msg.sender != duelAddress) revert DuelSide__Unauthorized();
        uint256 _duelFee = address(this).balance * (duelFee * 100) / 10000;
        uint256 _payoutAmount = address(this).balance - _duelFee;
        (bool payoutSuccess, ) = _payoutAddress.call{value: _payoutAmount}("");
        (bool feeSuccess, ) = payable(_duelWallet).call{value: _duelFee}("");
        if (!payoutSuccess || !feeSuccess) revert DuelSide__PayoutFailed();
        emit PayoutSent(_payoutAddress, address(this).balance);
    }

    function claimFunds() public {
        // TBD - check if duel has expired
        uint256 _amount = balances[msg.sender];
        balances[msg.sender] = 0;
        (bool success, ) = msg.sender.call{value: _amount}("");
        if (!success) revert DuelSide__PayoutFailed();
        emit FundsClaimed(msg.sender, _amount);
    }

}
