// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

contract SigUtils {
    bytes32 internal DOMAIN_SEPARATOR;

    bytes32 private constant TYPE_HASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");

    bytes32 public constant PLAYER_INVITATION_TYPE_HASH = 
        keccak256("InvitationVoucher(uint256 duelId,uint256 nonce,address playerB)");

    constructor(string memory name, string memory version, uint256 chainId, address verifierAddress) {
        DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                TYPE_HASH,
                keccak256(bytes(name)),
                keccak256(bytes(version)),
                chainId,
                verifierAddress
            )
        );
    }

    struct Invitation {
        uint256 duelId;
        uint256 nonce;
        address playerB;
    }

    // computes the hash of a permit
    function getStructHash(Invitation memory _invitation)
        internal
        pure
        returns (bytes32)
    {
        return
            keccak256(
                abi.encode(
                    PLAYER_INVITATION_TYPE_HASH,
                    _invitation.duelId,
                    _invitation.nonce,
                    _invitation.playerB
                )
            );
    }

    // computes the hash of the fully encoded EIP-712 message for the domain, which can be used to recover the signer
    function getTypedDataHash(Invitation memory _invitation)
        public
        view
        returns (bytes32)
    {
        return
            keccak256(
                abi.encodePacked(
                    "\x19\x01",
                    DOMAIN_SEPARATOR,
                    getStructHash(_invitation)
                )
            );
    }
}
