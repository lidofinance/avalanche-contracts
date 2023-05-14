// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

// Test support
import "forge-std/Script.sol";
import "forge-std/console.sol";

import "../test/helpers.sol";

// Contracts for deploy
import "../OracleManager.sol";
import "../Oracle.sol";
import "../AvaLido.sol";

contract Deploy is Script, Helpers {
    // Role details
    // TODO: This should be divided into roles rather than used for everything
    address proxyAdmin = 0x999a1D7349249B2a93B512f4ffcBF03DB760d15B; // N.B. The proxy admin MUST be different from all other admin addresses.
    address pauseAdmin = 0x000f54f73696298dEDffB4c37f8B6564F486EAA3;
    address oracleAdmin = 0x8e7D0f159e992cfC0ee28D55C600106482a818Ea;
    address mpcAdmin = 0x8e7D0f159e992cfC0ee28D55C600106482a818Ea;

    // Address constants
    address lidoFeeAddress = 0x11144C7f850415Ac4Fb446A6fE76b1DbD533FC55;
    address authorFeeAddress = 0x222D9E71E9f66e0B7cB2Ba837Be1B9B87052e612;

    // Constants
    address[] oracleAllowlist = [
        0x03C1196617387899390d3a98fdBdfD407121BB67,
        0x6C58f6E7DB68D9F75F2E417aCbB67e7Dd4e413bf,
        0xa7bB9405eAF98f36e2683Ba7F36828e260BD0018
    ];

    // Deploy contracts
    // Usage: forge script src/deploy/Deploy.t.sol --sig "deploy()" --broadcast --rpc-url <RPC_URL> --private-key <PRIVATE_KEY>
    // Syntax is identical to `cast`
    function deploy() public {
        // Create a transaction
        vm.startBroadcast();

        // MPC manager
        MpcManager _mpcManager = new MpcManager();
        MpcManager mpcManager = MpcManager(address(proxyWrapped(address(_mpcManager), proxyAdmin)));

        // Oracle manager
        OracleManager _oracleManager = new OracleManager();
        OracleManager oracleManager = OracleManager(address(proxyWrapped(address(_oracleManager), proxyAdmin)));
        oracleManager.initialize(oracleAdmin, oracleAllowlist);

        // Oracle
        uint256 epochDuration = 150;
        Oracle _oracle = new Oracle();
        Oracle oracle = Oracle(address(proxyWrapped(address(_oracle), proxyAdmin)));
        oracle.initialize(oracleAdmin, address(oracleManager), epochDuration);
        oracleManager.setOracleAddress(address(oracle));

        // Validator selector
        ValidatorSelector _validatorSelector = new ValidatorSelector();
        ValidatorSelector validatorSelector = ValidatorSelector(
            address(proxyWrapped(address(_validatorSelector), proxyAdmin))
        );
        validatorSelector.initialize(address(oracle));

        // AvaLido
        AvaLido _lido = new AvaLido();
        AvaLido lido = AvaLido(address(proxyWrapped(address(_lido), proxyAdmin)));
        lido.initialize(lidoFeeAddress, authorFeeAddress, address(validatorSelector), address(mpcManager));

        // // Treasuries
        Treasury pTreasury = new Treasury(address(lido));
        Treasury rTreasury = new Treasury(address(lido));
        lido.setPrincipalTreasuryAddress(address(pTreasury));
        lido.setRewardTreasuryAddress(address(rTreasury));

        // // MPC manager setup
        mpcManager.initialize(mpcAdmin, pauseAdmin, address(lido), address(pTreasury), address(rTreasury));

        // End transaction
        vm.stopBroadcast();

        console.log("Deployed AvaLido", address(lido));
        console.log("Deployed Validator Selector", address(validatorSelector));
        console.log("Deployed Oracle", address(oracle));
        console.log("Deployed Oracle Manager", address(oracleManager));
        console.log("Deployed MPC Manager", address(mpcManager));
    }
}
