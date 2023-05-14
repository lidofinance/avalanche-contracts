// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import {Test} from "forge-std/Test.sol";
import {console2 as console} from "forge-std/console2.sol";

import "./helpers.sol";

import "../Oracle.sol";
import "../OracleManager.sol";

contract OracleTest is Test, Helpers {
    Oracle oracle;

    event EpochDurationChanged(uint256 epochDuration);
    event OracleManagerAddressChanged(address newOracleManagerAddress);
    event OracleReportReceived(uint256 epochId);

    address[] ORACLE_MEMBERS = [
        WHITELISTED_ORACLE_1,
        WHITELISTED_ORACLE_2,
        WHITELISTED_ORACLE_3,
        WHITELISTED_ORACLE_4,
        WHITELISTED_ORACLE_5
    ];
    address ORACLE_MANAGER_CONTRACT_ADDRESS = 0xaFf132430941797A06ae017Ab2E9c5e791D5DF2C;
    uint256 epochId = 100;
    uint256 epochDuration = 100;
    string fakeNodeId = VALIDATOR_1;
    string[] validators = [VALIDATOR_1, VALIDATOR_2];

    function setUp() public {
        Oracle _oracle = new Oracle();
        oracle = Oracle(proxyWrapped(address(_oracle), ROLE_PROXY_ADMIN));
        oracle.initialize(ORACLE_ADMIN_ADDRESS, ORACLE_MANAGER_CONTRACT_ADDRESS, epochDuration);
    }

    function testOracleConstructor() public {
        assertEq(oracle.oracleManagerContract(), ORACLE_MANAGER_CONTRACT_ADDRESS);
    }

    // -------------------------------------------------------------------------
    //  Report functionality
    // -------------------------------------------------------------------------

    function testReceiveFinalizedReport() public {
        Validator[] memory reportData = new Validator[](1);
        reportData[0] = ValidatorHelpers.packValidator(0, 100);

        // Epoch id should be 0 to start
        assertEq(oracle.latestFinalizedEpochId(), 0);

        vm.expectEmit(false, false, false, true);
        emit OracleReportReceived(epochId);

        vm.prank(ORACLE_MANAGER_CONTRACT_ADDRESS);
        oracle.receiveFinalizedReport(epochId, reportData);

        // Epoch id should be 100 after report
        assertEq(oracle.latestFinalizedEpochId(), 100);

        Validator[] memory dataFromContract = oracle.getAllValidatorsByEpochId(epochId);
        assertEq(keccak256(abi.encode(reportData)), keccak256(abi.encode(dataFromContract)));
        assertEq(oracle.latestFinalizedEpochId(), epochId);
    }

    function testReceiveFinalizedReportAfterSkippedEpochs() public {
        Validator[] memory reportData = new Validator[](1);
        reportData[0] = ValidatorHelpers.packValidator(0, 100);

        // First report, epoch id should be 100
        vm.prank(ORACLE_MANAGER_CONTRACT_ADDRESS);
        oracle.receiveFinalizedReport(epochId, reportData);
        assertEq(oracle.latestFinalizedEpochId(), 100);

        // Second report for epoch id of 500 should be able to be accepted
        uint256 muchLaterEpochId = 500;
        vm.prank(ORACLE_MANAGER_CONTRACT_ADDRESS);
        oracle.receiveFinalizedReport(muchLaterEpochId, reportData);

        Validator[] memory dataFromContract = oracle.getAllValidatorsByEpochId(muchLaterEpochId);
        assertEq(keccak256(abi.encode(reportData)), keccak256(abi.encode(dataFromContract)));
        assertEq(oracle.latestFinalizedEpochId(), muchLaterEpochId);
    }

    function testCannotReceiveFinalizedReportForEpochsNotMatchingDuration() public {
        Validator[] memory reportData = new Validator[](1);
        reportData[0] = ValidatorHelpers.packValidator(0, 100);

        // First report, epoch id should be 100
        vm.prank(ORACLE_MANAGER_CONTRACT_ADDRESS);
        oracle.receiveFinalizedReport(epochId, reportData);
        assertEq(oracle.latestFinalizedEpochId(), 100);

        // Second report for epoch id of 300, should still be accepted even though the next ought to be 200
        uint256 invalidEpochId = 150;
        vm.startPrank(ORACLE_MANAGER_CONTRACT_ADDRESS);
        vm.expectRevert(Oracle.InvalidReportingEpoch.selector);
        oracle.receiveFinalizedReport(invalidEpochId, reportData);
        vm.stopPrank();
    }

    function testUnauthorizedReceiveFinalizedReport() public {
        Validator[] memory reportData = new Validator[](1);
        reportData[0] = ValidatorHelpers.packValidator(0, 100);
        vm.expectRevert(Oracle.OnlyOracleManagerContract.selector);
        oracle.receiveFinalizedReport(epochId, reportData);
    }

    function testCannotReceiveFinalizedReportTwice() public {
        Validator[] memory reportData = new Validator[](1);
        reportData[0] = ValidatorHelpers.packValidator(0, 100);

        vm.expectEmit(false, false, false, true);
        emit OracleReportReceived(epochId);

        vm.prank(ORACLE_MANAGER_CONTRACT_ADDRESS);
        oracle.receiveFinalizedReport(epochId, reportData);

        // Should fail because epoch is already finalized
        vm.startPrank(ORACLE_MANAGER_CONTRACT_ADDRESS);
        vm.expectRevert(Oracle.EpochAlreadyFinalized.selector);
        oracle.receiveFinalizedReport(epochId, reportData);
        vm.stopPrank();
    }

    function testOldReportDoesNotUpdateLatest() public {
        uint256 reportingEpochId = 200;
        Validator[] memory reportData = new Validator[](1);
        reportData[0] = ValidatorHelpers.packValidator(0, 100);

        vm.startPrank(ORACLE_MANAGER_CONTRACT_ADDRESS);
        oracle.receiveFinalizedReport(reportingEpochId, reportData);

        // Epoch id should be 200 after report
        assertEq(oracle.latestFinalizedEpochId(), 200);

        // Send an old report, expect revert
        vm.expectRevert(Oracle.InvalidReportingEpoch.selector);
        oracle.receiveFinalizedReport(reportingEpochId - epochDuration, reportData);

        // Latest should still be original epoch
        assertEq(oracle.latestFinalizedEpochId(), reportingEpochId);
    }

    function testCurrentReportableEpoch() public {
        // Assume we deploy at block 1337 with an epoch duration of 100
        // Current reportable block should be 1300
        vm.roll(1337);
        assertEq(oracle.currentReportableEpoch(), 1300);
    }

    // -------------------------------------------------------------------------
    //  Management
    // -------------------------------------------------------------------------

    function testChangeOracleManagerAddress() public {
        address newManagerAddress = 0x3e46faFf7369B90AA23fdcA9bC3dAd274c41E8E2;
        vm.expectEmit(false, false, false, true);
        emit OracleManagerAddressChanged(newManagerAddress);

        vm.prank(ORACLE_ADMIN_ADDRESS);
        oracle.setOracleManagerAddress(newManagerAddress);
    }

    function testUnauthorizedChangeOracleManagerAddress() public {
        address newManagerAddress = 0x3e46faFf7369B90AA23fdcA9bC3dAd274c41E8E2;
        vm.expectRevert(
            "AccessControl: account 0x34a1d3fff3958843c43ad80f30b94c510645c316 is missing role 0x34a4d1a1986ad857ac4bae77830874ee3b64b359bb6bdc3f73a14cff3bb32bf6"
        );
        oracle.setOracleManagerAddress(newManagerAddress);
    }

    function testChangeRoleOracleAdmin() public {
        // Assert correct role assignment from deploy
        assertTrue(oracle.hasRole(ROLE_ORACLE_ADMIN, ORACLE_ADMIN_ADDRESS));

        // User 2 has no roles.
        assertTrue(!oracle.hasRole(ROLE_ORACLE_ADMIN, USER2_ADDRESS));

        // User 2 doesn't have permission to grant roles, so this should revert.
        vm.expectRevert(
            "AccessControl: account 0x220866b1a2219f40e72f5c628b65d54268ca3a9d is missing role 0x0000000000000000000000000000000000000000000000000000000000000000"
        );
        vm.prank(USER2_ADDRESS);
        oracle.grantRole(ROLE_ORACLE_ADMIN, USER2_ADDRESS);

        // But the contract deployer does have permission.
        vm.prank(DEPLOYER_ADDRESS);
        oracle.grantRole(ROLE_ORACLE_ADMIN, USER2_ADDRESS);

        // User 2 now has a role 🎉
        assertTrue(oracle.hasRole(ROLE_ORACLE_ADMIN, USER2_ADDRESS));
    }

    function testStartNodeUpdate() public {
        assertTrue(!oracle.isUpdatingNodes());
        vm.prank(ORACLE_ADMIN_ADDRESS);
        oracle.startNodeIDUpdate();
        assertTrue(oracle.isUpdatingNodes());
    }

    function testStartNodeUpdateRemoveData() public {
        Validator[] memory reportData = new Validator[](1);
        reportData[0] = ValidatorHelpers.packValidator(0, 100);

        vm.prank(ORACLE_MANAGER_CONTRACT_ADDRESS);
        oracle.receiveFinalizedReport(epochId, reportData);

        assertEq(oracle.latestFinalizedEpochId(), 100);
        Validator[] memory vals = oracle.getLatestValidators();
        assertEq(vals.length, 1);

        vm.prank(ORACLE_ADMIN_ADDRESS);
        oracle.startNodeIDUpdate();
        Validator[] memory newVals = oracle.getLatestValidators();
        assertEq(newVals.length, 0);
    }

    function testStartNodeUpdateWhileUpdating() public {
        assertTrue(!oracle.isUpdatingNodes());
        vm.startPrank(ORACLE_ADMIN_ADDRESS);
        oracle.startNodeIDUpdate();
        assertTrue(oracle.isUpdatingNodes());

        vm.expectRevert(Oracle.InvalidNodeIDUpdate.selector);
        oracle.startNodeIDUpdate();
    }

    function testAddNodeIDsStartStop() public {
        vm.startPrank(ORACLE_ADMIN_ADDRESS);
        oracle.startNodeIDUpdate();

        string[] memory nodes = new string[](2);
        nodes[0] = "foo";
        nodes[1] = "bar";
        oracle.appendNodeIDs(nodes);

        oracle.endNodeIDUpdate();
        assertTrue(!oracle.isUpdatingNodes());
        assertEq(oracle.validatorCount(), 2);
    }

    function testAddNodeIDsMultiple() public {
        vm.startPrank(ORACLE_ADMIN_ADDRESS);
        oracle.startNodeIDUpdate();

        string[] memory nodes = new string[](2);
        nodes[0] = "foo";
        nodes[1] = "bar";
        oracle.appendNodeIDs(nodes);

        assertEq(oracle.validatorCount(), 2);

        string[] memory nodes2 = new string[](2);
        nodes2[0] = "baz";
        nodes2[1] = "qux";
        oracle.appendNodeIDs(nodes2);

        assertEq(oracle.validatorCount(), 4);
    }

    function testChangeEpochDuration() public {
        uint256 newEpochDuration = 500;
        vm.expectEmit(false, false, false, true);
        emit EpochDurationChanged(newEpochDuration);

        vm.prank(ORACLE_ADMIN_ADDRESS);
        oracle.setEpochDuration(newEpochDuration);
    }

    function testUnauthorizedChangeEpochDuration() public {
        uint256 newEpochDuration = 500;
        vm.expectRevert(
            "AccessControl: account 0x34a1d3fff3958843c43ad80f30b94c510645c316 is missing role 0x34a4d1a1986ad857ac4bae77830874ee3b64b359bb6bdc3f73a14cff3bb32bf6"
        );
        oracle.setEpochDuration(newEpochDuration);
    }

    function testChangeEpochDurationToZero() public {
        uint256 newEpochDuration = 0;
        vm.startPrank(ORACLE_ADMIN_ADDRESS);
        vm.expectRevert(Oracle.InvalidEpochDuration.selector);
        oracle.setEpochDuration(newEpochDuration);
        vm.stopPrank();
    }
}
