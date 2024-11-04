// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

error DuelImplementation__OnlyFactory();
error DuelImplementation__OnlyJudge();
error DuelImplementation__OnlyPlayerB();
error DuelImplementation__FundingTimeExceeded();
error DuelImplementation__JudgeAlreadyAccepted();
error DuelImplementation__NotDecidingTime();
error DuelImplementation__InvalidETHValue();
error DuelImplementation__FundingFailed();
error DuelImplementation__InvalidWinner();
error DuelImplementation__PayoutFailed();

// data:
//  - duel wallet for fee
//  - description
//  - status
//  - options
//  - amount
//  - expirationDate
// functions:
//  - set status
//  - finish duel
//  - send payout

interface IDuel {
    function setOptionsAddresses(address _optionA, address _optionB) external;
}

contract Duel is UUPSUpgradeable, OwnableUpgradeable, IDuel {
    enum Status {
        DRAFT,
        ACTIVE,
        COMPLETED
    }

    address public factory;
    uint256 public duelId;
    address public duelWallet;
    bool public judgeAccepted;
    bool public playerBAccepted;
    address public optionA;
    address public optionB;
    address public payoutA;
    address public payoutB;
    address public playerA;
    address public playerB;
    address public judge;
    uint256 public creationTime;
    uint256 public fundingTime;
    uint256 public decidingTime;
    string public title;
    string public optionADescription; // tbd
    string public optionBDescription; // tbd
    Status public status; // tbd

    modifier onlyDuringFundingTime() {
        if (block.timestamp > creationTime + fundingTime)
            revert DuelImplementation__FundingTimeExceeded();
        _;
    }

    modifier onlyDuringDecidingTime() {
        if (
            block.timestamp < creationTime + fundingTime ||
            block.timestamp > creationTime + fundingTime + decidingTime
        ) revert DuelImplementation__NotDecidingTime();
        _;
    }

    event NewDuelWallet(address newWallet);
    event ParticipantAccepted(address participant);
    event DuelCompleted(address winner);

    function initialize(
        uint256 _duelId,
        address _factory,
        address _duelWallet,
        string memory _title,
        string memory _optionADescription,
        string memory _optionBDescription,
        address _payoutA,
        address _playerA,
        address _playerB,
        uint256 _fundingTime,
        uint256 _decidingTime,
        address _judge
    ) public initializer {
        __Ownable_init(_playerA);
        __UUPSUpgradeable_init();
        duelId = _duelId;
        factory = _factory;
        duelWallet = _duelWallet;
        title = _title;
        optionADescription = _optionADescription;
        optionBDescription = _optionBDescription;
        payoutA = _payoutA;
        playerA = _playerA;
        playerB = _playerB;
        creationTime = block.timestamp;
        fundingTime = _fundingTime;
        decidingTime = _decidingTime;
        judge = _judge;
    }

    function judgeAccept() public onlyDuringFundingTime {
        if (msg.sender != judge) revert DuelImplementation__OnlyJudge();
        if (judgeAccepted) revert DuelImplementation__JudgeAlreadyAccepted();
        judgeAccepted = true;
        emit ParticipantAccepted(judge);
    }

    function playerBAccept(address _payoutB) public payable onlyDuringFundingTime {
        if (msg.sender != playerB) revert DuelImplementation__OnlyPlayerB();
        if (msg.value == 0) revert DuelImplementation__InvalidETHValue();
        payoutB = _payoutB;
        (bool success, ) = optionB.call{value: msg.value}("");
        if (!success) revert DuelImplementation__FundingFailed();
        playerBAccepted = true;
        emit ParticipantAccepted(playerB);
    }

    function judgeDecide(address _winner) public onlyDuringDecidingTime {
        if (msg.sender != judge) revert DuelImplementation__OnlyJudge();
        if (_winner != optionA && _winner != optionB)
            revert DuelImplementation__InvalidWinner();

        // Send payout to winner
        (bool sentPayoutA, ) = optionA.call(
            abi.encodeWithSignature("sendPayout(address)", _winner)
        );
        (bool sentPayoutB, ) = optionB.call(
            abi.encodeWithSignature("sendPayout(address)", _winner)
        );
        if (!sentPayoutA || !sentPayoutB)
            revert DuelImplementation__PayoutFailed();

        emit DuelCompleted(_winner);
    }

    function setOptionsAddresses(address _optionA, address _optionB) public {
        if (msg.sender != factory) revert DuelImplementation__OnlyFactory();
        optionA = _optionA;
        optionB = _optionB;
    }

    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyOwner {}
}
