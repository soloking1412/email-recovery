// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

/* solhint-disable no-console, gas-custom-errors */

import { console } from "forge-std/console.sol";
import { EmailAuth } from "@zk-email/ether-email-auth-contracts/src/EmailAuth.sol";
import { SafeRecoveryCommandHandler } from "src/handlers/SafeRecoveryCommandHandler.sol";
import { SafeEmailRecoveryModule } from "src/modules/SafeEmailRecoveryModule.sol";
import { BaseDeployScript } from "../BaseDeployScript.s.sol";

contract DeploySafeNativeRecovery_Script is BaseDeployScript {
    address public verifier;
    address public dkim;
    address public emailAuthImpl;
    address public commandHandler;
    uint256 public minimumDelay;
    address public killSwitchAuthorizer;

    address public initialOwner;
    address public dkimRegistrySigner;
    uint256 public dkimDelay;
    uint256 public salt;

    function run() public override {
        super.run();
        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));
        verifier = vm.envOr("VERIFIER", address(0));
        dkim = vm.envOr("DKIM_REGISTRY", address(0));
        emailAuthImpl = vm.envOr("EMAIL_AUTH_IMPL", address(0));
        commandHandler = vm.envOr("COMMAND_HANDLER", address(0));
        minimumDelay = vm.envOr("MINIMUM_DELAY", uint256(0));
        killSwitchAuthorizer = vm.envAddress("KILL_SWITCH_AUTHORIZER");

        initialOwner = vm.addr(vm.envUint("PRIVATE_KEY"));
        dkimRegistrySigner = vm.envOr("DKIM_SIGNER", address(0));
        dkimDelay = vm.envOr("DKIM_DELAY", uint256(0));
        salt = vm.envOr("CREATE2_SALT", uint256(0));

        if (verifier == address(0)) {
            verifier = deployVerifier(initialOwner, salt);
        }

        if (dkim == address(0)) {
            dkim = deployUserOverrideableDKIMRegistry(
                initialOwner, dkimRegistrySigner, dkimDelay, salt
            );
        }

        if (emailAuthImpl == address(0)) {
            emailAuthImpl = address(new EmailAuth{ salt: bytes32(salt) }());
            console.log("EmailAuth implemenation deployed at", emailAuthImpl);
        }

        if (commandHandler == address(0)) {
            commandHandler = address(new SafeRecoveryCommandHandler{ salt: bytes32(salt) }());
            console.log("SafeRecoveryCommandHandler deployed at", commandHandler);
        }

        address module = address(
            new SafeEmailRecoveryModule{ salt: bytes32(salt) }(
                verifier,
                address(dkim),
                emailAuthImpl,
                commandHandler,
                minimumDelay,
                killSwitchAuthorizer
            )
        );

        console.log("SafeEmailRecoveryModule deployed at  ", vm.toString(module));

        vm.stopBroadcast();
    }
}
