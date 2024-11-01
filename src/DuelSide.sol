// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

error DuelSide__Unauthorized();
error DuelSide__PayoutFailed();

contract DuelSide {
    
    address public duelAddress;
    uint256 public amount;
    uint256 public fundingTime;
    string public option;


    event PayoutSent(address indexed payoutAddress, uint256 amount);

    constructor(
        address _duelAddress,
        string memory _option,
        uint256 _amount,
        uint256 _fundingTime
    ) payable {
        duelAddress = _duelAddress;
        amount = _amount;
        fundingTime = _fundingTime;
        option = _option;
    }

    receive() external payable {}

    function sendPayout(address payable _payoutAddress) public {
        if(msg.sender != duelAddress) revert DuelSide__Unauthorized();
        (bool success, ) = _payoutAddress.call{value: address(this).balance}(
            ""
        );
        if (!success) revert DuelSide__PayoutFailed();
        emit PayoutSent(_payoutAddress, address(this).balance);
    }
}
