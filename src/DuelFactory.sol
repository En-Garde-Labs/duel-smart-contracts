// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {IDuel} from "./Duel.sol";
import {DuelOption} from "./DuelOption.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";

error DuelFactory__InvalidAddress();
error DuelFactory__InvalidDurations();
error DuelFactory__InvalidTargetAmount();
error DuelFactory__InvalidETHValue();
error DuelFactory__InvalidImplementation();
error DuelFactory__InvalidPlayer();
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

    /**
     * @dev Constructor to initialize the DuelFactory contract.
     * @param _owner Address of the contract owner (admin).
     * @param _duelImplementation Address of the `Duel` implementation contract.
     * @param _duelWallet Address of the wallet for collecting duel fees.
     * @param _duelFee The fee percentage in basis points (e.g., 125 for 1.25%).
     */
    constructor(
        address _owner,
        address _duelImplementation,
        address _duelWallet,
        uint256 _duelFee
    ) Ownable(_owner) {
        if (_duelFee > 10000) revert DuelFactory__InvalidFee(); // Max 100% in basis points
        if (_duelImplementation == address(0) || _duelWallet == address(0))
            revert DuelFactory__InvalidAddress();
        duelImplementation = _duelImplementation;
        duelWallet = _duelWallet;
        duelFee = _duelFee;
    }

    /**
     * @notice Creates a new duel by deploying a UUPS proxy for the `Duel` contract.
     * @dev This function deploys a new proxy and two `DuelOption` contracts for the duel.
     * @param _title Title of the duel.
     * @param _payoutA Address for payout wallet of player A.
     * @param _targetAmount The target amount of funding for both Option contracts in wei.
     * @param _fundingDuration Duration in seconds for the funding period.
     * @param _decisionLockDuration Duration in seconds for the decision lock period.
     * @param _judge Address of the judge who can decide the duel outcome. If address(0), the duel will be decided by the players.
     * @param _invitationSigner Address of the signer of invitations (cannot be zero).
     * @return The address of the newly created duel (proxy) contract.
     */
    function createDuel(
        string memory _title,
        address _payoutA,
        uint256 _targetAmount,
        uint256 _fundingDuration,
        uint256 _decisionLockDuration,
        address _judge,
        address _invitationSigner
    ) external payable whenNotPaused returns (address) {
        if (_judge == msg.sender) revert DuelFactory__InvalidPlayer();
        if (_targetAmount == 0) revert DuelFactory__InvalidTargetAmount();
        if (msg.value == 0 || msg.value > _targetAmount)
            revert DuelFactory__InvalidETHValue();
        if (_decisionLockDuration < _fundingDuration)
            revert DuelFactory__InvalidDurations();
        uint256 duelId = _nextDuelId++;
        ERC1967Proxy proxy = new ERC1967Proxy(
            duelImplementation,
            abi.encodeWithSignature(
                "initialize(uint256,address,address,string,uint256,address,address,uint256,uint256,address,address)",
                duelId,
                address(this),
                duelWallet,
                _title, // duel's title
                _targetAmount, // amount of the duel
                _payoutA, // payout wallet for option A
                msg.sender, // player A
                _fundingDuration, // funding time limit
                _decisionLockDuration, // deciding time starts
                _judge, // judge address
                _invitationSigner
            )
        );

        DuelOption DuelOptionA = new DuelOption{value: msg.value}(
            address(proxy),
            _targetAmount,
            _fundingDuration,
            duelFee,
            msg.sender
        );
        DuelOption DuelOptionB = new DuelOption(
            address(proxy),
            _targetAmount,
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

    /**
     * @notice Sets a new implementation address for deploying UUPS proxies.
     * @dev Only the contract owner can call this function.
     * @param _newImplementation The address of the new `Duel` implementation contract.
     */
    function setImplementation(address _newImplementation) external onlyOwner {
        if (_newImplementation.code.length == 0)
            revert DuelFactory__InvalidImplementation();
        duelImplementation = _newImplementation;
        emit NewImplementation(_newImplementation);
    }

    /**
     * @notice Sets a new wallet address for collecting duel fees.
     * @dev Only the contract owner can call this function.
     * @param _newWallet The address of the new duel wallet.
     */
    function setDuelWallet(address _newWallet) external onlyOwner {
        duelWallet = _newWallet;
        emit NewDuelWallet(_newWallet);
    }

    /**
     * @notice Updates the fee percentage for new duels.
     * @dev Only the contract owner can call this function.
     * @param _newFee The new fee percentage in basis points (e.g., 125 for 1.25%).
     */
    function setFee(uint256 _newFee) external onlyOwner {
        if (_newFee > 10000) revert DuelFactory__InvalidFee(); // Max 100% in basis points
        duelFee = _newFee;
        emit NewFee(_newFee);
    }

    /**
     * @notice Pauses duel creation and updates by the factory.
     * @dev Only the contract owner can call this function.
     */
    function pause() external onlyOwner whenNotPaused {
        _pause();
    }

    /**
     * @notice Resumes duel creation and updates by the factory.
     * @dev Only the contract owner can call this function.
     */
    function unpause() external onlyOwner whenPaused {
        _unpause();
    }
}
