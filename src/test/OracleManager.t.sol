// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import {Test} from "forge-std/Test.sol";
import {console2 as console} from "forge-std/console2.sol";
import "openzeppelin-contracts/contracts/access/AccessControlEnumerable.sol";

import "./helpers.sol";

import "../OracleManager.sol";
import "../Oracle.sol";

contract OracleManagerTest is Test, Helpers {
    OracleManager oracleManager;
    Oracle oracle;

    event OracleAddressChanged(address oracleAddress);
    event OracleMemberAdded(address member);
    event OracleMemberRemoved(address member);
    event OracleReportSent(uint256 epochId);

    address[] ORACLE_MEMBERS = [
        WHITELISTED_ORACLE_1,
        WHITELISTED_ORACLE_2,
        WHITELISTED_ORACLE_3,
        WHITELISTED_ORACLE_4,
        WHITELISTED_ORACLE_5
    ];
    uint256 epochId = 100;
    address anotherAddressForTesting = 0x3e46faFf7369B90AA23fdcA9bC3dAd274c41E8E2;
    string[] nodeIds = [VALIDATOR_1, VALIDATOR_2];

    function setUp() public {
        OracleManager _oracleManager = new OracleManager();
        oracleManager = OracleManager(proxyWrapped(address(_oracleManager), ROLE_PROXY_ADMIN));
        oracleManager.initialize(ORACLE_ADMIN_ADDRESS, ORACLE_MEMBERS);

        uint256 epochDuration = 100;
        Oracle _oracle = new Oracle();
        oracle = Oracle(proxyWrapped(address(_oracle), ROLE_PROXY_ADMIN));
        oracle.initialize(ORACLE_ADMIN_ADDRESS, address(oracleManager), epochDuration);

        vm.startPrank(ORACLE_ADMIN_ADDRESS);
        oracle.startNodeIDUpdate();
        oracle.appendNodeIDs(nodeIds);
        oracle.endNodeIDUpdate();
        vm.stopPrank();
    }

    // -------------------------------------------------------------------------
    //  Initialization
    // -------------------------------------------------------------------------

    function testOracleContractAddressNotSet() public {
        Validator[] memory reportData = new Validator[](1);
        reportData[0] = ValidatorHelpers.packValidator(0, 100);

        vm.roll(epochId + 1);

        vm.prank(ORACLE_MEMBERS[0]);
        vm.expectRevert(OracleManager.OracleContractAddressNotSet.selector);
        oracleManager.receiveMemberReport(epochId, reportData);

        vm.prank(ORACLE_ADMIN_ADDRESS);
        oracleManager.setOracleAddress(address(oracle));
        vm.prank(ORACLE_MEMBERS[0]);
        oracleManager.receiveMemberReport(epochId, reportData);
        assertEq(oracleManager.retrieveHashedDataCount(epochId, keccak256(abi.encode(reportData))), 1);
    }

    // -------------------------------------------------------------------------
    //  Report functionality
    // -------------------------------------------------------------------------

    function testReceiveMemberReportWithoutQuorum() public {
        vm.prank(ORACLE_ADMIN_ADDRESS);
        oracleManager.setOracleAddress(address(oracle));

        vm.roll(epochId + 1);

        Validator[] memory reportData = new Validator[](1);
        reportData[0] = ValidatorHelpers.packValidator(0, 100);
        vm.prank(ORACLE_MEMBERS[0]);
        oracleManager.receiveMemberReport(epochId, reportData);
    }

    function testReceiveMemberReportWithQuorum() public {
        vm.prank(ORACLE_ADMIN_ADDRESS);
        oracleManager.setOracleAddress(address(oracle));

        Validator[] memory reportDataOne = new Validator[](1);
        reportDataOne[0] = ValidatorHelpers.packValidator(0, 100);
        Validator[] memory reportDataTwo = new Validator[](1);
        reportDataTwo[0] = ValidatorHelpers.packValidator(1, 200);

        vm.roll(epochId + 1);

        vm.prank(ORACLE_MEMBERS[0]);
        oracleManager.receiveMemberReport(epochId, reportDataOne);
        vm.prank(ORACLE_MEMBERS[1]);
        oracleManager.receiveMemberReport(epochId, reportDataTwo);
        vm.prank(ORACLE_MEMBERS[2]);
        oracleManager.receiveMemberReport(epochId, reportDataOne);
        vm.prank(ORACLE_MEMBERS[3]);
        oracleManager.receiveMemberReport(epochId, reportDataTwo);
        vm.prank(ORACLE_MEMBERS[4]);
        vm.expectEmit(false, false, false, true);
        emit OracleReportSent(epochId);
        oracleManager.receiveMemberReport(epochId, reportDataOne);
    }

    function testCannotReportForFinalizedEpoch() public {
        vm.prank(ORACLE_ADMIN_ADDRESS);
        oracleManager.setOracleAddress(address(oracle));

        Validator[] memory reportDataOne = new Validator[](1);
        reportDataOne[0] = ValidatorHelpers.packValidator(0, 100);

        vm.roll(epochId + 1);

        vm.prank(ORACLE_MEMBERS[0]);
        oracleManager.receiveMemberReport(epochId, reportDataOne);
        vm.prank(ORACLE_MEMBERS[1]);
        oracleManager.receiveMemberReport(epochId, reportDataOne);
        vm.prank(ORACLE_MEMBERS[2]);
        oracleManager.receiveMemberReport(epochId, reportDataOne);
        vm.prank(ORACLE_MEMBERS[3]);
        vm.expectRevert(OracleManager.EpochAlreadyFinalized.selector);
        oracleManager.receiveMemberReport(epochId, reportDataOne);
    }

    function testOracleCannotReportTwice() public {
        vm.prank(ORACLE_ADMIN_ADDRESS);
        oracleManager.setOracleAddress(address(oracle));

        Validator[] memory reportDataOne = new Validator[](1);
        reportDataOne[0] = ValidatorHelpers.packValidator(0, 100);
        vm.roll(epochId + 1);
        vm.startPrank(ORACLE_MEMBERS[0]);
        oracleManager.receiveMemberReport(epochId, reportDataOne);
        vm.expectRevert(OracleManager.OracleAlreadyReported.selector);
        oracleManager.receiveMemberReport(epochId, reportDataOne);
        vm.stopPrank();
    }

    function testUnauthorizedReceiveMemberReport() public {
        vm.prank(ORACLE_ADMIN_ADDRESS);
        oracleManager.setOracleAddress(address(oracle));

        Validator[] memory reportData = new Validator[](1);
        reportData[0] = ValidatorHelpers.packValidator(0, 100);
        vm.expectRevert(OracleManager.OracleMemberNotFound.selector);
        oracleManager.receiveMemberReport(epochId, reportData);
    }

    function testCannotReceiveReportWhenPaused() public {
        vm.prank(ORACLE_ADMIN_ADDRESS);
        oracleManager.pause();
        Validator[] memory reportDataOne = new Validator[](1);
        reportDataOne[0] = ValidatorHelpers.packValidator(0, 100);
        vm.prank(ORACLE_MEMBERS[0]);
        vm.expectRevert("Pausable: paused");
        oracleManager.receiveMemberReport(epochId, reportDataOne);
    }

    function testCannotReportInvalidIndex() public {
        vm.prank(ORACLE_ADMIN_ADDRESS);
        oracleManager.setOracleAddress(address(oracle));

        Validator[] memory reportDataInvalid = new Validator[](1);
        reportDataInvalid[0] = ValidatorHelpers.packValidator(123, 100);

        vm.roll(epochId + 1);
        vm.expectRevert(OracleManager.InvalidValidatorIndex.selector);
        vm.prank(ORACLE_MEMBERS[0]);
        oracleManager.receiveMemberReport(epochId, reportDataInvalid);
    }

    function testCannotReportForEpochNotMatchingDuration() public {
        // If the epoch duration is 100 we should not be able to report for
        // epochs that aren't epochId % epochDuration = 0
        vm.prank(ORACLE_ADMIN_ADDRESS);
        oracleManager.setOracleAddress(address(oracle));

        // Setup first report for epoch id 100
        Validator[] memory reportData = new Validator[](1);
        reportData[0] = ValidatorHelpers.packValidator(0, 100);
        vm.prank(address(oracleManager));
        oracle.receiveFinalizedReport(100, reportData);
        assertEq(oracle.latestFinalizedEpochId(), 100);

        // Cannot report for epoch id such as 150
        vm.roll(150);
        vm.prank(ORACLE_MEMBERS[0]);
        vm.expectRevert(OracleManager.InvalidReportingEpoch.selector);
        oracleManager.receiveMemberReport(150, reportData);
    }

    function testCannotReportForEarlierEpoch() public {
        vm.prank(ORACLE_ADMIN_ADDRESS);
        oracleManager.setOracleAddress(address(oracle));

        // Setup first report for epoch id 200
        Validator[] memory reportData = new Validator[](1);
        reportData[0] = ValidatorHelpers.packValidator(0, 100);
        vm.prank(address(oracleManager));
        oracle.receiveFinalizedReport(200, reportData);
        assertEq(oracle.latestFinalizedEpochId(), 200);

        vm.roll(210);
        vm.prank(ORACLE_MEMBERS[0]);
        vm.expectRevert(OracleManager.InvalidReportingEpoch.selector);
        oracleManager.receiveMemberReport(100, reportData);
    }

    function testCurrentReportableEpoch() public {
        // Setup first report for epoch id 100
        Validator[] memory reportData = new Validator[](1);
        reportData[0] = ValidatorHelpers.packValidator(0, 100);
        vm.prank(address(oracleManager));
        oracle.receiveFinalizedReport(100, reportData);
        assertEq(oracle.latestFinalizedEpochId(), 100);

        // Assume oracle misses report for the next epoch id 200.
        // They should be able to send a report for epoch id 300.
        vm.roll(303);
        vm.prank(ORACLE_ADMIN_ADDRESS);
        oracleManager.setOracleAddress(address(oracle));
        vm.prank(ORACLE_MEMBERS[0]);
        oracleManager.receiveMemberReport(300, reportData);
    }

    // -------------------------------------------------------------------------
    //  Oracle management
    // -------------------------------------------------------------------------

    function testAddOracleMember() public {
        vm.prank(ORACLE_ADMIN_ADDRESS);
        vm.expectEmit(false, false, false, true);
        emit OracleMemberAdded(anotherAddressForTesting);
        oracleManager.addOracleMember(anotherAddressForTesting);

        // Assert it exists in the whitelist array
        address[] memory whitelistedOraclesArrayFromContract = oracleManager.getWhitelistedOracles();
        assertTrue(addressArrayContains(anotherAddressForTesting, whitelistedOraclesArrayFromContract));
        // Assert it exists in the whitelist mapping
        assertTrue(oracleManager.whitelistedOraclesMapping(anotherAddressForTesting));
    }

    function testUnauthorizedAddOracleMember() public {
        vm.expectRevert(
            "AccessControl: account 0x34a1d3fff3958843c43ad80f30b94c510645c316 is missing role 0x34a4d1a1986ad857ac4bae77830874ee3b64b359bb6bdc3f73a14cff3bb32bf6"
        );
        oracleManager.addOracleMember(anotherAddressForTesting);
    }

    function testCannotAddOracleMemberAgain() public {
        vm.prank(ORACLE_ADMIN_ADDRESS);
        vm.expectRevert(OracleManager.OracleMemberExists.selector);
        oracleManager.addOracleMember(ORACLE_MEMBERS[0]);
    }

    function testRemoveOracleMember() public {
        vm.prank(ORACLE_ADMIN_ADDRESS);
        vm.expectEmit(false, false, false, true);
        emit OracleMemberRemoved(ORACLE_MEMBERS[2]);
        oracleManager.removeOracleMember(ORACLE_MEMBERS[2]);

        // Assert it doesn't exist in the whitelist array
        address[] memory whitelistedOraclesArrayFromContract = oracleManager.getWhitelistedOracles();
        assertTrue(!addressArrayContains(anotherAddressForTesting, whitelistedOraclesArrayFromContract));
        // Assert it doesn't exist in the whitelist mapping
        assertTrue(!oracleManager.whitelistedOraclesMapping(anotherAddressForTesting));
    }

    function testUnauthorizedRemoveOracleMember() public {
        vm.expectRevert(
            "AccessControl: account 0x34a1d3fff3958843c43ad80f30b94c510645c316 is missing role 0x34a4d1a1986ad857ac4bae77830874ee3b64b359bb6bdc3f73a14cff3bb32bf6"
        );
        oracleManager.removeOracleMember(anotherAddressForTesting);
    }

    function testCannotRemoveOracleMemberIfNotPresent() public {
        vm.prank(ORACLE_ADMIN_ADDRESS);
        vm.expectRevert(OracleManager.OracleMemberNotFound.selector);
        oracleManager.removeOracleMember(0xf195179eEaE3c8CAB499b5181721e5C57e4769b2);
    }

    function testProtocolNotStuckAfterSetList() public {
        vm.prank(ORACLE_ADMIN_ADDRESS);
        oracleManager.setOracleAddress(address(oracle));

        Validator[] memory reportDataOne = new Validator[](1);
        reportDataOne[0] = ValidatorHelpers.packValidator(0, 100);

        vm.roll(epochId + 1);

        // Add a report for a valid epoch
        vm.prank(ORACLE_MEMBERS[0]);
        oracleManager.receiveMemberReport(100, reportDataOne);

        string[] memory newNodes = new string[](1);
        newNodes[0] = "test";

        // Change the nodeID list
        vm.startPrank(ORACLE_ADMIN_ADDRESS);
        oracle.startNodeIDUpdate();
        oracle.appendNodeIDs(newNodes);
        oracle.endNodeIDUpdate();
        vm.stopPrank();

        vm.roll(220);

        // Ensure we are able to move forwards and get quoroum for epoch 2
        vm.prank(ORACLE_MEMBERS[0]);
        oracleManager.receiveMemberReport(200, reportDataOne);
        vm.prank(ORACLE_MEMBERS[1]);
        oracleManager.receiveMemberReport(200, reportDataOne);

        vm.expectEmit(false, false, false, true);
        emit OracleReportSent(200);

        vm.prank(ORACLE_MEMBERS[2]);
        oracleManager.receiveMemberReport(200, reportDataOne);
    }

    // -------------------------------------------------------------------------
    //  Address and auth management
    // -------------------------------------------------------------------------

    function testSetOracleAddress() public {
        vm.prank(ORACLE_ADMIN_ADDRESS);
        vm.expectEmit(false, false, false, true);
        emit OracleAddressChanged(anotherAddressForTesting);
        oracleManager.setOracleAddress(anotherAddressForTesting);
    }

    function testUnauthorizedSetOracleAddress() public {
        vm.expectRevert(
            "AccessControl: account 0x34a1d3fff3958843c43ad80f30b94c510645c316 is missing role 0x34a4d1a1986ad857ac4bae77830874ee3b64b359bb6bdc3f73a14cff3bb32bf6"
        );
        oracleManager.setOracleAddress(anotherAddressForTesting);
    }
}
