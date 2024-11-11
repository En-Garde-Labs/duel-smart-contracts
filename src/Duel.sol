// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

error DuelImplementation__OnlyFactory();
error DuelImplementation__OnlyJudge();
error DuelImplementation__OnlyPlayerB();
error DuelImplementation__FundingDurationExceeded();
error DuelImplementation__AlreadyAccepted(address);
error DuelImplementation__NotDecisionPeriod();
error DuelImplementation__InvalidETHValue();
error DuelImplementation__FundingFailed();
error DuelImplementation__InvalidWinner();
error DuelImplementation__PayoutFailed();
error DuelImplementation__DuelExpired();
error DuelImplementation__Unauthorized();

import {console} from "forge-std/console.sol";

interface IDuel {
    function setOptionsAddresses(address _optionA, address _optionB) external;

    function updateStatus() external;

    function duelExpiredOrFinished() external view returns (bool);
}

contract Duel is UUPSUpgradeable, OwnableUpgradeable, IDuel {
    address public factory;
    uint256 public duelId;
    address public duelWallet;
    bool public judgeAccepted;
    bool public playerBAccepted;
    bool public decisionMade;
    address public optionA;
    address public optionB;
    address public playerA;
    address public playerB;
    address public judge;
    address public agreedWinner;
    uint256 public creationTime;
    uint256 public fundingDuration;
    uint256 public decisionLockDuration;
    string public title;
    bool public duelExpiredOrFinished;
    mapping(address player => address payoutAddress) public payoutAddresses;
    mapping(address player => bool) public playerAgreed;

    event ParticipantAccepted(address indexed participant);
    event PayoutAddressSet(
        address indexed player,
        address indexed payoutAddress
    );

    event DuelCompleted(address indexed winner);
    event DuelExpired();
    event PayoutSent();

    modifier onlyDuringFundingPeriod() {
        if (block.timestamp > creationTime + fundingDuration)
            revert DuelImplementation__FundingDurationExceeded();
        _;
    }

    modifier onlyDuringDecisionPeriod() {
        uint256 decisionStartTime = creationTime + decisionLockDuration;
        uint256 decisionEndTime = decisionStartTime + fundingDuration; // decisionDuration equals fundingDuration
        if (
            block.timestamp < decisionStartTime ||
            block.timestamp > decisionEndTime
        ) revert DuelImplementation__NotDecisionPeriod();
        _;
    }

    modifier duelIsActive() {
        if (duelExpiredOrFinished) revert DuelImplementation__DuelExpired();
        _;
    }

    modifier updatesStatus() {
        updateStatus();
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        uint256 _duelId,
        address _factory,
        address _duelWallet,
        string memory _title,
        address _payoutA,
        address _playerA,
        address _playerB,
        uint256 _fundingDuration,
        uint256 _decisionLockDuration,
        address _judge
    ) public initializer {
        __Ownable_init(_playerA);
        __UUPSUpgradeable_init();
        if (_judge == address(0)) {
            judgeAccepted = true;
        }
        duelId = _duelId;
        factory = _factory;
        duelWallet = _duelWallet;
        title = _title;
        payoutAddresses[_playerA] = _payoutA;
        playerA = _playerA;
        playerB = _playerB;
        creationTime = block.timestamp;
        fundingDuration = _fundingDuration;
        decisionLockDuration = _decisionLockDuration;
        judge = _judge;
    }

    function judgeAccept() public onlyDuringFundingPeriod updatesStatus {
        if (msg.sender != judge) revert DuelImplementation__OnlyJudge();
        if (judgeAccepted) revert DuelImplementation__AlreadyAccepted(judge);
        judgeAccepted = true;

        emit ParticipantAccepted(judge);
    }

    function playerBAccept(
        address _payoutB
    ) public payable onlyDuringFundingPeriod updatesStatus {
        if (playerBAccepted)
            revert DuelImplementation__AlreadyAccepted(playerB);
        if (msg.sender != playerB) revert DuelImplementation__OnlyPlayerB();
        if (msg.value == 0) revert DuelImplementation__InvalidETHValue();

        payoutAddresses[msg.sender] = _payoutB;
        playerBAccepted = true;

        (bool success, ) = optionB.call{value: msg.value}("");
        if (!success) revert DuelImplementation__FundingFailed();

        emit ParticipantAccepted(playerB);
    }

    function judgeDecide(
        address _winner
    ) public onlyDuringDecisionPeriod updatesStatus duelIsActive {
        if (msg.sender != judge) revert DuelImplementation__OnlyJudge();
        if (_winner != optionA && _winner != optionB)
            revert DuelImplementation__InvalidWinner();

        decisionMade = true;
        duelExpiredOrFinished = true; // Mark the duel as finished
        _distributePayout(_winner);
        emit DuelCompleted(_winner);
    }

    function playersAgree(
        address _winner
    ) public onlyDuringDecisionPeriod updatesStatus duelIsActive {
        require(judge == address(0), "Judge exists");
        require(msg.sender == playerA || msg.sender == playerB, "Not a player");
        if (_winner != optionA && _winner != optionB)
            revert DuelImplementation__InvalidWinner();
        require(!playerAgreed[msg.sender], "Player already agreed");

        if (agreedWinner == address(0)) {
            agreedWinner = _winner;
            playerAgreed[msg.sender] = true;
        } else {
            require(agreedWinner == _winner, "Players disagree on winner");
            playerAgreed[msg.sender] = true;
            if (playerAgreed[playerA] && playerAgreed[playerB]) {
                decisionMade = true;
                duelExpiredOrFinished = true; // Mark the duel as finished
                _distributePayout(_winner);
                emit DuelCompleted(_winner);
            }
        }
    }

    function setPayoutAddress(
        address _payoutAddress
    ) public onlyDuringFundingPeriod updatesStatus {
        if (msg.sender != playerA && msg.sender != playerB)
            revert DuelImplementation__Unauthorized();
        payoutAddresses[msg.sender] = _payoutAddress;

        emit PayoutAddressSet(msg.sender, _payoutAddress);
    }

    function setOptionsAddresses(address _optionA, address _optionB) public {
        if (msg.sender != factory) revert DuelImplementation__OnlyFactory();
        optionA = _optionA;
        optionB = _optionB;
    }

    function updateStatus() public {
        // Check if funding time has ended without acceptance
        if (block.timestamp > creationTime + fundingDuration) {
            if (!judgeAccepted || !playerBAccepted) {
                duelExpiredOrFinished = true;
                emit DuelExpired();
                return; // Early exit since duel has expired
            }
        }

        // Calculate decision period start and end times
        uint256 decisionStartTime = creationTime + decisionLockDuration;
        uint256 decisionEndTime = decisionStartTime + fundingDuration; // decisionDuration equals fundingDuration

        // Check if decision period has ended without a decision
        if (block.timestamp > decisionEndTime) {
            if (!decisionMade) {
                duelExpiredOrFinished = true;
                emit DuelExpired();
            }
        }
    }

    function _distributePayout(address _winner) internal {
        address winningPlayer;
        if (_winner == optionA) {
            winningPlayer = playerA;
        } else if (_winner == optionB) {
            winningPlayer = playerB;
        } else {
            revert DuelImplementation__InvalidWinner();
        }
        address payoutAddress = payoutAddresses[winningPlayer];

        (bool sentPayoutA, ) = optionA.call(
            abi.encodeWithSignature(
                "sendPayout(address,address)",
                payoutAddress,
                duelWallet
            )
        );
        (bool sentPayoutB, ) = optionB.call(
            abi.encodeWithSignature(
                "sendPayout(address,address)",
                payoutAddress,
                duelWallet
            )
        );
        if (!sentPayoutA || !sentPayoutB)
            revert DuelImplementation__PayoutFailed();

        emit PayoutSent();
    }

    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyOwner {}
}
