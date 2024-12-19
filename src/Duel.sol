// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {EIP712Upgradeable} from "@openzeppelin/contracts-upgradeable/utils/cryptography/EIP712Upgradeable.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {BitMaps} from "@openzeppelin/contracts/utils/structs/BitMaps.sol";

error DuelImplementation__OnlyFactory();
error DuelImplementation__OnlyJudge();
error DuelImplementation__UsedNonce();
error DuelImplementation__FundingDurationExceeded();
error DuelImplementation__AlreadyAccepted(address);
error DuelImplementation__NotDecisionPeriod();
error DuelImplementation__InvalidETHValue();
error DuelImplementation__FundingFailed();
error DuelImplementation__InvalidWinner();
error DuelImplementation__PayoutFailed();
error DuelImplementation__DuelExpired();
error DuelImplementation__Unauthorized();
error DuelImplementation__JudgeExists();
error DuelImplementation__UnauthorizedInvitation();
error DuelImplementation__InvalidInvitationSigner();

interface IDuel {
    function setOptionsAddresses(address _optionA, address _optionB) external;

    function updateStatus() external;

    function duelExpiredOrFinished() external view returns (bool);
}

contract Duel is UUPSUpgradeable, OwnableUpgradeable, IDuel, EIP712Upgradeable {
    BitMaps.BitMap internal _processedNonces;

    uint256 public duelId;
    address public factory;
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
    uint256 public amount;
    uint256 public creationTime;
    uint256 public fundingDuration;
    uint256 public decisionLockDuration;
    string public title;
    bool public duelExpiredOrFinished;
    address public invitationSigner;
    mapping(address player => address payoutAddress) public payoutAddresses;
    mapping(address player => bool) public playerAgreed;

    bytes32 private constant PLAYER_INVITATION_TYPE_HASH = 
        keccak256("InvitationVoucher(uint256 duelId,uint256 nonce,address playerB)");

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

    /**
     * @notice Initializes the `Duel` contract with the required parameters.
     * @dev This function is called by the `DuelFactory` upon deployment.
     * @param _duelId Unique identifier for the duel.
     * @param _factory Address of the factory contract that deployed this duel.
     * @param _duelWallet Address to which the fee will be sent.
     * @param _title Title or description of the duel.
     * @param _amount The target amount of funding for both Option contracts in wei.
     * @param _payoutA Address for player A's payout wallet.
     * @param _playerA Address of player A, the creator of the duel.
     * @param _fundingDuration Duration in seconds for the funding period.
     * @param _decisionLockDuration Duration in seconds for the decision lock period.
     * @param _judge Address of the judge for the duel (can be zero if no judge).
     * @param _invitationSigner Address of the duel invitation signer (cannot be zero).
     */
    function initialize(
        uint256 _duelId,
        address _factory,
        address _duelWallet,
        string memory _title,
        uint256 _amount,
        address _payoutA,
        address _playerA,
        uint256 _fundingDuration,
        uint256 _decisionLockDuration,
        address _judge,
        address _invitationSigner
    ) external initializer {
        __Ownable_init(_duelWallet);
        __EIP712_init(_title, "1");
        __UUPSUpgradeable_init();
        if (_judge == address(0)) {
            judgeAccepted = true;
        }
        if (_invitationSigner == address(0))
            revert DuelImplementation__InvalidInvitationSigner();
        duelId = _duelId;
        factory = _factory;
        duelWallet = _duelWallet;
        title = _title;
        amount = _amount;
        payoutAddresses[_playerA] = _payoutA;
        playerA = _playerA;
        creationTime = block.timestamp;
        fundingDuration = _fundingDuration;
        decisionLockDuration = _decisionLockDuration;
        judge = _judge;
        invitationSigner = _invitationSigner;
    }

    /**
     * @notice Allows the judge to accept their role in the duel during the funding period.
     * @dev Only callable by the judge during the funding period, and only once.
     * @return success Boolean indicating successful acceptance.
     */
    function judgeAccept()
        external
        onlyDuringFundingPeriod
        updatesStatus
        returns (bool)
    {
        if (msg.sender != judge) revert DuelImplementation__OnlyJudge();
        if (judgeAccepted) revert DuelImplementation__AlreadyAccepted(judge);
        judgeAccepted = true;

        emit ParticipantAccepted(judge);
        return true;
    }

    /**
     * @notice Allows player B to accept the duel and fund their side.
     * @dev Only callable by player B during the funding period and requires ETH to fund OptionB contract.
     * @param _payoutB Address for player B's payout wallet.
     * @param _nonce The nonce of the invitation.
     * @param _signature The signature of the invitation to accept.
     * @return success Boolean indicating successful acceptance.
     */
    function playerBAccept(
        address _payoutB,
        uint256 _nonce,
        bytes memory _signature
    ) external payable onlyDuringFundingPeriod updatesStatus returns (bool) {
        if (playerBAccepted)
            revert DuelImplementation__AlreadyAccepted(playerB);
        if (msg.value == 0) revert DuelImplementation__InvalidETHValue();
        if (BitMaps.get(_processedNonces, _nonce)) revert DuelImplementation__UsedNonce();
        verifyPlayerInvitationSignature(_nonce, _signature);
        BitMaps.set(_processedNonces, _nonce);

        playerB = msg.sender;
        payoutAddresses[msg.sender] = _payoutB;
        playerBAccepted = true;

        (bool success, ) = optionB.call{value: msg.value}("");
        if (!success) revert DuelImplementation__FundingFailed();

        emit ParticipantAccepted(playerB);
        return true;
    }

    /**
     * @notice Allows the judge to decide the winner during the decision period.
     * @dev Only callable by the judge if a judge is assigned and the decision period is active.
     * @param _winner Address of the winning option (either optionA or optionB).
     * @return success Boolean indicating successful decision.
     */
    function judgeDecide(
        address _winner
    )
        external
        onlyDuringDecisionPeriod
        updatesStatus
        duelIsActive
        returns (bool)
    {
        if (msg.sender != judge) revert DuelImplementation__OnlyJudge();
        if (_winner != optionA && _winner != optionB)
            revert DuelImplementation__InvalidWinner();

        decisionMade = true;
        duelExpiredOrFinished = true; // Mark the duel as finished
        _distributePayout(_winner);
        emit DuelCompleted(_winner);
        return true;
    }

    /**
     * @notice Allows players A and B to agree on a winner when there is no judge.
     * @dev Only callable by players A and B during the decision period.
     * @param _winner Address of the winning option (either optionA or optionB).
     * @return success Boolean indicating successful agreement.
     */
    function playersAgree(
        address _winner
    )
        external
        onlyDuringDecisionPeriod
        updatesStatus
        duelIsActive
        returns (bool)
    {
        if (judge != address(0)) revert DuelImplementation__JudgeExists();
        if (msg.sender != playerA && msg.sender != playerB)
            revert DuelImplementation__Unauthorized();
        if (_winner != optionA && _winner != optionB)
            revert DuelImplementation__InvalidWinner();
        if (playerAgreed[msg.sender])
            revert DuelImplementation__AlreadyAccepted(msg.sender);

        if (agreedWinner == address(0)) {
            agreedWinner = _winner;
            playerAgreed[msg.sender] = true;
        } else {
            if (agreedWinner != _winner)
                revert DuelImplementation__InvalidWinner();
            playerAgreed[msg.sender] = true;
            if (playerAgreed[playerA] && playerAgreed[playerB]) {
                decisionMade = true;
                duelExpiredOrFinished = true; // Mark the duel as finished
                _distributePayout(_winner);
                emit DuelCompleted(_winner);
            }
        }
        return true;
    }

    /**
     * @notice Sets the payout address for either player A or player B during the funding period.
     * @param _payoutAddress The address where the payout should be sent for the caller.
     * @return success Boolean indicating successful update of payout address.
     */
    function setPayoutAddress(
        address _payoutAddress
    ) external onlyDuringFundingPeriod updatesStatus returns (bool) {
        if (msg.sender != playerA && msg.sender != playerB)
            revert DuelImplementation__Unauthorized();
        payoutAddresses[msg.sender] = _payoutAddress;

        emit PayoutAddressSet(msg.sender, _payoutAddress);
        return true;
    }

    /**
     * @notice Sets the addresses of option A and option B contracts.
     * @dev This function is only callable by the factory contract when creating the Duel.
     * @param _optionA Address of the contract representing option A.
     * @param _optionB Address of the contract representing option B.
     */
    function setOptionsAddresses(address _optionA, address _optionB) external {
        if (msg.sender != factory) revert DuelImplementation__OnlyFactory();
        optionA = _optionA;
        optionB = _optionB;
    }

    /**
     * @notice Updates the status of the duel based on funding and decision periods.
     * @dev This function checks whether the funding or decision period has ended and marks the duel as expired if applicable.
     */
    function updateStatus() public {
        // Check if funding time has ended without acceptance
        if (block.timestamp > creationTime + fundingDuration) {
            if (
                !judgeAccepted ||
                !playerBAccepted ||
                optionA.balance < amount ||
                optionB.balance < amount
            ) {
                duelExpiredOrFinished = true;
                emit DuelExpired();
                return; // Early exit since duel has expired
            }
        }

        // Calculate decision period start and end times
        uint256 decisionStartTime = creationTime + decisionLockDuration;
        // decisionDuration equals fundingDuration
        uint256 decisionEndTime = decisionStartTime + fundingDuration;

        // Check if decision period has ended
        if (block.timestamp > decisionEndTime) {
            duelExpiredOrFinished = true;
            emit DuelExpired();
        }
    }

    /**
     * @notice Verifies that provided signature corresponds to a valid invitation.
     * @dev This internal function follows the EIP-712 scheme for validating signed typed data.
     * @param _nonce Nonce of the signature to prevent replay attacks.
     * @param _signature Invitation signature to validate.
     */
    function verifyPlayerInvitationSignature(uint256 _nonce, bytes memory _signature) internal view {
        bytes32 digest =
            _hashTypedDataV4(
                keccak256(
                    abi.encode(
                        PLAYER_INVITATION_TYPE_HASH,
                        duelId,
                        _nonce,
                        msg.sender
                    )
                )
            );
        address signer = ECDSA.recover(digest, _signature);
        if (invitationSigner != signer) revert DuelImplementation__UnauthorizedInvitation();
    }

    /**
     * @notice Distributes the payout to the winner after a decision is made.
     * @dev This internal function calls `sendPayout` on both options to send funds to the winner and fee to the duel wallet.
     * @param _winner Address of the winning option (either optionA or optionB).
     */
    function _distributePayout(address _winner) private {
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

    /**
     * @notice Authorizes upgrades to the `Duel` implementation contract.
     * @dev This function restricts upgrades to only the contract owner.
     * @param newImplementation Address of the new implementation contract.
     */
    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyOwner {}

    uint256[50] private __gap;
}
