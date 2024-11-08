// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

error DuelImplementation__OnlyFactory();
error DuelImplementation__OnlyJudge();
error DuelImplementation__OnlyPlayerB();
error DuelImplementation__FundingTimeExceeded();
error DuelImplementation__AlreadyAccepted(address);
error DuelImplementation__NotDecidingTime();
error DuelImplementation__InvalidETHValue();
error DuelImplementation__FundingFailed();
error DuelImplementation__InvalidWinner();
error DuelImplementation__PayoutFailed();
error DuelImplementation__DuelExpired();
error DuelImplementation__NoJudge();
error DuelImplementation__Unauthorized();

interface IDuel {
    function setOptionsAddresses(address _optionA, address _optionB) external;

    enum Status {
        DRAFT,
        ACTIVE,
        COMPLETED,
        EXPIRED
    }

    function updateStatus() external;

    function getStatus() external view returns (uint8);
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
    address public payoutA;
    address public payoutB;
    address public playerA;
    address public playerB;
    address public judge;
    address public agreedWinner;
    uint256 public creationTime;
    uint256 public fundingTime;
    uint256 public decidingTime;
    string public title;
    Status public status;
    mapping(address => bool) public playerAgreed;

    event NewDuelWallet(address indexed newWallet);
    event ParticipantAccepted(address indexed participant);
    event PayoutAddressSet(
        address indexed player,
        address indexed payoutAddress
    );
    event DuelActivated();
    event DuelCompleted(address indexed winner);
    event DuelExpired();
    event PayoutSent();

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
        uint256 _fundingTime,
        uint256 _decidingTime,
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
        payoutA = _payoutA;
        playerA = _playerA;
        playerB = _playerB;
        creationTime = block.timestamp;
        fundingTime = _fundingTime;
        decidingTime = _decidingTime;
        judge = _judge;
    }

    function judgeAccept() public onlyDuringFundingTime updatesStatus {
        if (judge == address(0)) revert DuelImplementation__NoJudge();
        if (msg.sender != judge) revert DuelImplementation__OnlyJudge();
        if (judgeAccepted) revert DuelImplementation__AlreadyAccepted(judge);
        judgeAccepted = true;

        if (playerBAccepted) {
            status = Status.ACTIVE;
        }

        emit ParticipantAccepted(judge);
    }

    function playerBAccept(
        address _payoutB
    ) public payable onlyDuringFundingTime updatesStatus {
        if (playerBAccepted)
            revert DuelImplementation__AlreadyAccepted(playerB);
        if (msg.sender != playerB) revert DuelImplementation__OnlyPlayerB();
        if (msg.value == 0) revert DuelImplementation__InvalidETHValue();

        payoutB = _payoutB;
        playerBAccepted = true;

        if (judgeAccepted) {
            status = Status.ACTIVE;
        }

        (bool success, ) = optionB.call{value: msg.value}("");
        if (!success) revert DuelImplementation__FundingFailed();

        emit ParticipantAccepted(playerB);
    }

    function judgeDecide(
        address _winner
    ) public onlyDuringDecidingTime updatesStatus {
        if (status != Status.ACTIVE) revert DuelImplementation__DuelExpired();
        if (msg.sender != judge) revert DuelImplementation__OnlyJudge();
        if (_winner != optionA && _winner != optionB)
            revert DuelImplementation__InvalidWinner();

        decisionMade = true;
        updateStatus();

        _distributePayout(_winner);
        emit DuelCompleted(_winner);
    }

    function playersAgree(address _winner) public updatesStatus {
        require(judge == address(0), "Judge exists");
        require(msg.sender == playerA || msg.sender == playerB, "Not a player");
        require(_winner == optionA || _winner == optionB, "Invalid winner");
        require(status == Status.ACTIVE, "Duel not active");
        require(!playerAgreed[msg.sender], "Player already agreed");

        if (agreedWinner == address(0)) {
            agreedWinner = _winner;
            playerAgreed[msg.sender] = true;
        } else {
            require(agreedWinner == _winner, "Players disagree on winner");
            playerAgreed[msg.sender] = true;
            if (playerAgreed[playerA] && playerAgreed[playerB]) {
                decisionMade = true;
                updateStatus();
                _distributePayout(_winner);
                emit DuelCompleted(_winner);
            }
        }
    }

    function setPayoutAddress(
        address _payoutAddress
    ) public onlyDuringFundingTime updatesStatus {
        if (msg.sender == playerA) {
            payoutA = _payoutAddress;
        } else if (msg.sender == playerB) {
            payoutB = _payoutAddress;
        } else {
            revert DuelImplementation__Unauthorized();
        }
        emit PayoutAddressSet(msg.sender, _payoutAddress);
    }

    function setOptionsAddresses(address _optionA, address _optionB) public {
        if (msg.sender != factory) revert DuelImplementation__OnlyFactory();
        optionA = _optionA;
        optionB = _optionB;
    }

    function updateStatus() public {
        if (status == Status.DRAFT) {
            if (block.timestamp > creationTime + fundingTime) {
                if (!judgeAccepted || !playerBAccepted) {
                    status = Status.EXPIRED;
                    emit DuelExpired();
                } else {
                    status = Status.ACTIVE;
                    emit DuelActivated();
                }
            } else if (judgeAccepted && playerBAccepted) {
                status = Status.ACTIVE;
                emit DuelActivated();
            }
        } else if (status == Status.ACTIVE) {
            if (block.timestamp > creationTime + fundingTime + decidingTime) {
                if (!decisionMade) {
                    status = Status.EXPIRED;
                    emit DuelExpired();
                }
            } else if (decisionMade) {
                status = Status.COMPLETED;
            }
        }
    }

    function getStatus() public view returns (uint8) {
        return uint8(status);
    }

    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyOwner {}

    function _distributePayout(address _winner) internal {
        (bool sentPayoutA, ) = optionA.call(
            abi.encodeWithSignature(
                "sendPayout(address,address)",
                _winner,
                duelWallet
            )
        );
        (bool sentPayoutB, ) = optionB.call(
            abi.encodeWithSignature(
                "sendPayout(address,address)",
                _winner,
                duelWallet
            )
        );
        if (!sentPayoutA || !sentPayoutB)
            revert DuelImplementation__PayoutFailed();

        emit PayoutSent();
    }
}
