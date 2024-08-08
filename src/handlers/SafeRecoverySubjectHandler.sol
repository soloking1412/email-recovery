// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { IEmailRecoverySubjectHandler } from "../interfaces/IEmailRecoverySubjectHandler.sol";
import { ISafe } from "../interfaces/ISafe.sol";

/**
 * Handler contract that defines subject templates and how to validate them
 * This is a custom subject handler that will work with Safes and defines custom validation.
 */
contract SafeRecoverySubjectHandler is IEmailRecoverySubjectHandler {
    bytes4 public constant selector = bytes4(keccak256(bytes("swapOwner(address,address,address)")));

    error InvalidTemplateIndex(uint256 templateIdx, uint256 expectedTemplateIdx);
    error InvalidSubjectParams(uint256 paramsLength, uint256 expectedParamsLength);
    error InvalidOldOwner(address oldOwner);
    error InvalidNewOwner(address newOwner);

    /**
     * @notice Returns a hard-coded two-dimensional array of strings representing the subject
     * templates for an acceptance by a new guardian.
     * @return string[][] A two-dimensional array of strings, where each inner array represents a
     * set of fixed strings and matchers for a subject template.
     */
    function acceptanceSubjectTemplates() public pure returns (string[][] memory) {
        string[][] memory templates = new string[][](1);
        templates[0] = new string[](5);
        templates[0][0] = "Accept";
        templates[0][1] = "guardian";
        templates[0][2] = "request";
        templates[0][3] = "for";
        templates[0][4] = "{ethAddr}";
        return templates;
    }

    /**
     * @notice Returns a hard-coded two-dimensional array of strings representing the subject
     * templates for email recovery.
     * @return string[][] A two-dimensional array of strings, where each inner array represents a
     * set of fixed strings and matchers for a subject template.
     */
    function recoverySubjectTemplates() public pure returns (string[][] memory) {
        string[][] memory templates = new string[][](1);
        templates[0] = new string[](11);
        templates[0][0] = "Recover";
        templates[0][1] = "account";
        templates[0][2] = "{ethAddr}";
        templates[0][3] = "from";
        templates[0][4] = "old";
        templates[0][5] = "owner";
        templates[0][6] = "{ethAddr}";
        templates[0][7] = "to";
        templates[0][8] = "new";
        templates[0][9] = "owner";
        templates[0][10] = "{ethAddr}";
        return templates;
    }

    /**
     * @notice Extracts the account address to be recovered from the subject parameters of an
     * acceptance email.
     * @param subjectParams The subject parameters of the acceptance email.
     */
    function extractRecoveredAccountFromAcceptanceSubject(
        bytes[] calldata subjectParams,
        uint256 /* templateIdx */
    )
        public
        pure
        returns (address)
    {
        return abi.decode(subjectParams[0], (address));
    }

    /**
     * @notice Extracts the account address to be recovered from the subject parameters of a
     * recovery email.
     * @param subjectParams The subject parameters of the recovery email.
     */
    function extractRecoveredAccountFromRecoverySubject(
        bytes[] calldata subjectParams,
        uint256 /* templateIdx */
    )
        public
        pure
        returns (address)
    {
        return abi.decode(subjectParams[0], (address));
    }

    /**
     * @notice Validates the subject params for an acceptance email
     * @param templateIdx The index of the template used for acceptance
     * @param subjectParams The subject parameters of the recovery email
     * @return accountInEmail The account address in the acceptance email
     */
    function validateAcceptanceSubject(
        uint256 templateIdx,
        bytes[] calldata subjectParams
    )
        external
        pure
        returns (address)
    {
        if (templateIdx != 0) {
            revert InvalidTemplateIndex(templateIdx, 0);
        }
        if (subjectParams.length != 1) {
            revert InvalidSubjectParams(subjectParams.length, 1);
        }

        // The GuardianStatus check in acceptGuardian implicitly
        // validates the account, so no need to re-validate here
        address accountInEmail = abi.decode(subjectParams[0], (address));

        return accountInEmail;
    }

    /**
     * @notice Validates the subject params for an acceptance email
     * @param templateIdx The index of the template used for the recovery request
     * @param subjectParams The subject parameters of the recovery email
     * @return accountInEmail The account address in the acceptance email
     */
    function validateRecoverySubject(
        uint256 templateIdx,
        bytes[] calldata subjectParams
    )
        public
        view
        returns (address)
    {
        if (templateIdx != 0) {
            revert InvalidTemplateIndex(templateIdx, 0);
        }
        if (subjectParams.length != 3) {
            revert InvalidSubjectParams(subjectParams.length, 3);
        }

        address accountInEmail = abi.decode(subjectParams[0], (address));
        address oldOwnerInEmail = abi.decode(subjectParams[1], (address));
        address newOwnerInEmail = abi.decode(subjectParams[2], (address));

        bool isOldAddressOwner = ISafe(accountInEmail).isOwner(oldOwnerInEmail);
        if (!isOldAddressOwner) {
            revert InvalidOldOwner(oldOwnerInEmail);
        }

        bool isNewAddressOwner = ISafe(accountInEmail).isOwner(newOwnerInEmail);
        if (newOwnerInEmail == address(0) || isNewAddressOwner) {
            revert InvalidNewOwner(newOwnerInEmail);
        }

        return accountInEmail;
    }

    /**
     * @notice parses the recovery data hash from the subject params. The data hash is
     * verified against later when recovery is executed
     * @dev recoveryDataHash = keccak256(abi.encode(safeAccount, recoveryFunctionCalldata)). In the
     * context of recovery for a Safe, the first encoded value is the Safe account address. Normally,
     * this would be the validator address
     * @param templateIdx The index of the template used for the recovery request
     * @param subjectParams The subject parameters of the recovery email
     * @return recoveryDataHash The keccak256 hash of the recovery data
     */
    function parseRecoveryDataHash(
        uint256 templateIdx,
        bytes[] calldata subjectParams
    )
        external
        view
        returns (bytes32)
    {
        if (templateIdx != 0) {
            revert InvalidTemplateIndex(templateIdx, 0);
        }

        address accountInEmail = abi.decode(subjectParams[0], (address));
        address oldOwnerInEmail = abi.decode(subjectParams[1], (address));
        address newOwnerInEmail = abi.decode(subjectParams[2], (address));

        address previousOwnerInLinkedList =
            getPreviousOwnerInLinkedList(accountInEmail, oldOwnerInEmail);
        bytes memory swapOwnerCalldata = abi.encodeWithSelector(
            selector, previousOwnerInLinkedList, oldOwnerInEmail, newOwnerInEmail
        );
        return keccak256(abi.encode(accountInEmail, swapOwnerCalldata));
    }

    /**
     * @notice Gets the previous owner in the Safe owners linked list that points to the
     * owner passed into the function
     * @param safe The Safe account to query
     * @param oldOwner The owner address to get the previous owner for
     * @return previousOwner The previous owner in the Safe owners linked list pointing to the owner
     * passed in
     */
    function getPreviousOwnerInLinkedList(
        address safe,
        address oldOwner
    )
        internal
        view
        returns (address)
    {
        address[] memory owners = ISafe(safe).getOwners();
        uint256 length = owners.length;

        uint256 oldOwnerIndex;
        for (uint256 i; i < length; i++) {
            if (owners[i] == oldOwner) {
                oldOwnerIndex = i;
                break;
            }
        }
        address sentinelOwner = address(0x1);
        return oldOwnerIndex == 0 ? sentinelOwner : owners[oldOwnerIndex - 1];
    }
}
