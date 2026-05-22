// SPDX-License-Identifier: MIT
pragma solidity ^0.8.35;

// Solidity sketch matching SoLean.Examples.AAPQSource.integratedContract.
// This file is a documentation/audit fixture only. It is not parsed, compiled,
// or proved equivalent to the Lean models. The corresponding proved programs
// are AAWallet.validateProgram, PQVerifierWrapper.verifyProgram, and
// AAPQIntegration.validateIntegrated.

contract PQVerifierWrapper {
    uint256 public expectedPublicKeyLength; // slot 0
    uint256 public expectedSignatureLength; // slot 1
    uint256 public expectedDomain;          // slot 2

    // Modeled in Lean by SoLean.Env.verifier as an abstract oracle.
    function pqVerifier(
        uint256 publicKey,
        uint256 message,
        uint256 domain,
        uint256 signature
    ) internal view virtual returns (bool);

    function verify(
        uint256 publicKey,
        uint256 publicKeyLength,
        uint256 message,
        uint256 domain,
        uint256 signature,
        uint256 signatureLength
    ) external view {
        require(publicKeyLength == expectedPublicKeyLength);
        require(signatureLength == expectedSignatureLength);
        require(domain == expectedDomain);
        require(pqVerifier(publicKey, message, domain, signature));
    }
}

contract AAWallet {
    uint256 public nonce;         // slot 0
    uint256 public keyCommitment; // slot 1
    uint256 public domain;        // slot 2
    address public entryPoint;    // slot 3 (modeled as uint256 in Lean)

    // Modeled in Lean by SoLean.Env.verifier on the same oracle as the wrapper.
    function pqVerifier(
        uint256 publicKey,
        uint256 message,
        uint256 domain_,
        uint256 signature
    ) internal view virtual returns (bool);

    function validateUserOp(
        uint256 opHash,
        uint256 userOpNonce,
        uint256 userOpDomain,
        uint256 signature
    ) external {
        require(msg.sender == address(uint160(uint256(uint160(entryPoint)))));
        require(userOpNonce == nonce);
        require(userOpDomain == domain);
        require(pqVerifier(keyCommitment, opHash, domain, signature));
        nonce = nonce + 1; // checked add in Solidity 0.8.x
    }
}

// Reference integration shim corresponding to
// SoLean.Examples.AAPQIntegration.validateIntegrated. The two contracts are
// modeled as separate storage boundaries; the integration runs the wrapper,
// checks the key commitment matches the public key, then runs the wallet
// validation. External-call semantics, ABI decoding, calldata, memory, gas,
// events, and reentrancy are intentionally out of scope for this fixture.
contract AAPQIntegration {
    PQVerifierWrapper public wrapper;
    AAWallet public wallet;

    function validateIntegrated(
        uint256 publicKey,
        uint256 publicKeyLength,
        uint256 opHash,
        uint256 userOpNonce,
        uint256 userOpDomain,
        uint256 signature,
        uint256 signatureLength
    ) external {
        wrapper.verify(
            publicKey,
            publicKeyLength,
            opHash,
            userOpDomain,
            signature,
            signatureLength
        );
        require(wallet.keyCommitment() == publicKey);
        wallet.validateUserOp(opHash, userOpNonce, userOpDomain, signature);
    }
}
