// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {
    IUserOperationBuilder, PackedUserOperation
} from "src/interfaces/IUserOperationBuilder.sol";
import { ModeLib } from "erc7579/lib/ModeLib.sol";
import { Execution, ExecutionLib } from "erc7579/lib/ExecutionLib.sol";
import { IEntryPoint } from "@ERC4337/account-abstraction/contracts/interfaces/IEntryPoint.sol";
import { IERC7579Account } from "erc7579/interfaces/IERC7579Account.sol";

interface IPermissionChecker {
    function checkPermissionForSmartAccount(
        address smartAccount,
        bytes calldata permissionDataFromContext
    )
        external
        view
        returns (bytes32 permissionPrefix);
}

type ValidAfter is uint48;

type ValidUntil is uint48;

struct SingleSignerPermission {
    ValidUntil validUntil;
    ValidAfter validAfter;
    address signatureValidationAlgorithm;
    bytes signer;
    // TODO: change it to address[] and bytes[] to be able to
    // stack policies for a permission
    // as of now it is enough to have a single policy for demo purposes
    address policy;
    bytes policyData;
}

contract Safe7579UserOperationBuilder is IUserOperationBuilder {
    IEntryPoint internal immutable _entryPoint;

    constructor(address _entryPointAddress) {
        _entryPoint = IEntryPoint(_entryPointAddress);
    }

    function entryPoint() external view returns (address) {
        return address(_entryPoint);
    }

    function getNonce(
        address smartAccount,
        bytes calldata context
    )
        external
        view
        returns (uint256)
    {
        address validator = address(bytes20(context[0:20]));
        uint192 key = uint192(bytes24(bytes20(address(validator))));
        return _entryPoint.getNonce(address(smartAccount), key);
    }

    function getCallData(
        address smartAccount,
        Execution[] calldata executions,
        bytes calldata context
    )
        external
        view
        returns (bytes memory)
    {
        if (executions.length == 0) {
            revert("No executions provided");
        }
        if (executions.length == 1) {
            return abi.encodeCall(
                IERC7579Account.execute,
                (
                    ModeLib.encodeSimpleSingle(),
                    ExecutionLib.encodeSingle(
                        executions[0].target, executions[0].value, executions[0].callData
                    )
                )
            );
        } else {
            return abi.encodeCall(
                IERC7579Account.execute,
                (ModeLib.encodeSimpleBatch(), ExecutionLib.encodeBatch(executions))
            );
        }
        // TODO: add delegatecall, tryExecute and other execution modes handling
    }

    function getDummySignature(
        address smartAccount,
        Execution[] calldata executions,
        bytes calldata context
    )
        external
        view
        returns (bytes memory signature)
    {
        return context;
    }

    function getSignature(
        address smartAccount,
        PackedUserOperation calldata userOperation,
        bytes calldata context
    )
        external
        view
        returns (bytes memory signature)
    {
        address permissionValidator = address(bytes20(context[0:20]));

        // What if permission has already been set?
        bytes32 result = IPermissionChecker(permissionValidator).checkPermissionForSmartAccount(
            smartAccount, context[20:]
        );

        if (result == keccak256("Permission Not Enabled")) {
            // just use the full data required to enable the permission
            signature = getEnablePermissionValidatorSignatureFromContext(
                context[20:], userOperation.signature
            );
        } else {
            /* commented this out bc currently deployed permission validator is hardcode to 
             the check _isSessionEnableTransaction to alway return true */
            // just use the permissionId returned as result
            //signature = abi.encode(result, userOperation.signature);

            //so for now returning same signature as enable permissions
            signature = getEnablePermissionValidatorSignatureFromContext(
                context[20:], userOperation.signature
            );
        }
    }

    function getEnablePermissionValidatorSignatureFromContext(
        bytes calldata permissionDataFromContext,
        bytes calldata rawSignature
    )
        private
        pure
        returns (bytes memory)
    {
        (
            uint256 permissionIndex,
            SingleSignerPermission memory permission,
            bytes memory permissionEnableData,
            bytes memory permissionEnableSignature
        ) = abi.decode(
            permissionDataFromContext[1:], (uint256, SingleSignerPermission, bytes, bytes)
        );

        return abi.encodePacked(
            permissionDataFromContext[:1], //enable tx flag
            abi.encode(
                permissionIndex,
                permission,
                permissionEnableData,
                permissionEnableSignature,
                rawSignature
            )
        );
    }
}
