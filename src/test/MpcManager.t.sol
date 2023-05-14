// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import {Test} from "forge-std/Test.sol";
import {console2 as console} from "forge-std/console2.sol";

import "./helpers.sol";

import "../interfaces/IMpcManager.sol";
import "../MpcManager.sol";

contract MpcManagerTest is Test, Helpers {
    uint8 constant MPC_THRESHOLD = 1;
    bytes32 constant MPC_BIG_GROUP_ID = hex"270b05bac4f59f0c069249ee5d68364fc56b326bf6d63b8d5577fcd8c20c0900";
    bytes32 constant MPC_BIG_P01_ID = hex"270b05bac4f59f0c069249ee5d68364fc56b326bf6d63b8d5577fcd8c20c0901";
    bytes32 constant MPC_BIG_P02_ID = hex"270b05bac4f59f0c069249ee5d68364fc56b326bf6d63b8d5577fcd8c20c0902";
    bytes32 constant MPC_BIG_P03_ID = hex"270b05bac4f59f0c069249ee5d68364fc56b326bf6d63b8d5577fcd8c20c0903";
    bytes32 constant MPC_BIG_P04_ID = hex"270b05bac4f59f0c069249ee5d68364fc56b326bf6d63b8d5577fcd8c20c0904";
    bytes32 constant MPC_BIG_P05_ID = hex"270b05bac4f59f0c069249ee5d68364fc56b326bf6d63b8d5577fcd8c20c0905";
    bytes32 constant MPC_BIG_P06_ID = hex"270b05bac4f59f0c069249ee5d68364fc56b326bf6d63b8d5577fcd8c20c0906";
    bytes32 constant MPC_BIG_P07_ID = hex"270b05bac4f59f0c069249ee5d68364fc56b326bf6d63b8d5577fcd8c20c0907";
    bytes32 constant MPC_BIG_P08_ID = hex"270b05bac4f59f0c069249ee5d68364fc56b326bf6d63b8d5577fcd8c20c0908";
    bytes32 constant MPC_BIG_P09_ID = hex"270b05bac4f59f0c069249ee5d68364fc56b326bf6d63b8d5577fcd8c20c0909";
    bytes32 constant MPC_BIG_P10_ID = hex"270b05bac4f59f0c069249ee5d68364fc56b326bf6d63b8d5577fcd8c20c090a";
    bytes32 constant MPC_BIG_P11_ID = hex"270b05bac4f59f0c069249ee5d68364fc56b326bf6d63b8d5577fcd8c20c090b";
    bytes32 constant MPC_BIG_P12_ID = hex"270b05bac4f59f0c069249ee5d68364fc56b326bf6d63b8d5577fcd8c20c090c";
    bytes constant TOO_SHORT_PUKEY =
        hex"ee5cd601a19cd9bb95fe7be8b1566b73c51d3e7e375359c129b1d77bb4b3e6f06766bde6ff723360cee7f89abab428717f811f460ebf67f5186f75a9f4288d";

    bytes constant MESSAGE_TO_SIGN = bytes("foo");
    uint256 constant STAKE_AMOUNT = 30 ether;
    uint256 constant STAKE_START_TIME = 1640966400; // 2022-01-01
    uint256 constant STAKE_END_TIME = 1642176000; // 2022-01-15

    bytes32 constant UTXO_TX_ID = hex"5245afb3ad9c5c3c9430a7034464f42cee023f228d46ebcae7544759d2779caa";

    address AVALIDO_ADDRESS = 0x1000000000000000000000000000000000000001;

    address PRINCIPAL_TREASURY_ADDR = 0xd94fC5fd8812ddE061F420D4146bc88e03b6787c;
    address REWARD_TREASURY_ADDR = 0xe8025f13E6bF0Db21212b0Dd6AEBc4F3d1FB03ce;

    MpcManager mpcManager;
    bytes[] pubKeys = new bytes[](3);

    enum KeygenStatus {
        NOT_EXIST,
        REQUESTED,
        COMPLETED,
        CANCELED
    }
    event ParticipantAdded(bytes indexed publicKey, bytes32 groupId, uint256 index);
    event KeygenRequestAdded(bytes32 indexed groupId, uint256 requestNumber);
    event KeygenRequestCanceled(bytes32 indexed groupId, uint256 requestNumber);
    event KeyGenerated(bytes32 indexed groupId, bytes publicKey);
    event SignRequestAdded(uint256 requestId, bytes indexed publicKey, bytes message);
    event SignRequestStarted(uint256 requestId, bytes indexed publicKey, bytes message);
    event RequestStarted(bytes32 requestHash, uint256 participantIndices);
    event RequestFailed(bytes32 requestHash, bytes data);
    event StakeRequestAdded(
        uint256 requestId,
        bytes indexed publicKey,
        string nodeID,
        uint256 amount,
        uint256 startTime,
        uint256 endTime
    );
    event StakeRequestStarted(
        uint256 requestId,
        bytes indexed publicKey,
        uint256 participantIndices,
        string nodeID,
        uint256 amount,
        uint256 startTime,
        uint256 endTime
    );
    event ExportUTXORequest(
        bytes32 txId,
        uint32 outputIndex,
        address to,
        bytes indexed genPubKey,
        uint256 participantIndices
    );

    function resetParticipantPublicKeys() public {
        pubKeys[0] = MPC_PLAYER_1_PUBKEY;
        pubKeys[1] = MPC_PLAYER_2_PUBKEY;
        pubKeys[2] = MPC_PLAYER_3_PUBKEY;
    }

    function setUp() public {
        MpcManager _mpcManager = new MpcManager();
        mpcManager = MpcManager(proxyWrapped(address(_mpcManager), ROLE_PROXY_ADMIN));
        mpcManager.initialize(
            MPC_ADMIN_ADDRESS,
            PAUSE_ADMIN_ADDRESS,
            AVALIDO_ADDRESS,
            PRINCIPAL_TREASURY_ADDR,
            REWARD_TREASURY_ADDR
        );
        pubKeys[0] = MPC_PLAYER_1_PUBKEY;
        pubKeys[1] = MPC_PLAYER_2_PUBKEY;
        pubKeys[2] = MPC_PLAYER_3_PUBKEY;
    }

    // -------------------------------------------------------------------------
    //  Test cases
    // -------------------------------------------------------------------------
    function testCreateGroupTooBig() public {
        // Exceeding max allowed groupSize (=248)
        bytes[] memory pubKeysTooBig = new bytes[](249);
        for (uint256 i = 0; i < 249; i++) {
            pubKeysTooBig[i] = MPC_PLAYER_1_PUBKEY;
        }
        vm.prank(MPC_ADMIN_ADDRESS);
        vm.expectRevert(MpcManager.InvalidGroupSize.selector);
        mpcManager.createGroup(pubKeysTooBig, 200);
    }

    function testGroupOfSize12() public {
        bytes[] memory pubKeys12 = new bytes[](12);
        pubKeys12[0] = MPC_BIG_P01_PUBKEY;
        pubKeys12[1] = MPC_BIG_P02_PUBKEY;
        pubKeys12[2] = MPC_BIG_P03_PUBKEY;
        pubKeys12[3] = MPC_BIG_P04_PUBKEY;
        pubKeys12[4] = MPC_BIG_P05_PUBKEY;
        pubKeys12[5] = MPC_BIG_P06_PUBKEY;
        pubKeys12[6] = MPC_BIG_P07_PUBKEY;
        pubKeys12[7] = MPC_BIG_P08_PUBKEY;
        pubKeys12[8] = MPC_BIG_P09_PUBKEY;
        pubKeys12[9] = MPC_BIG_P10_PUBKEY;
        pubKeys12[10] = MPC_BIG_P11_PUBKEY;
        pubKeys12[11] = MPC_BIG_P12_PUBKEY;
        vm.prank(MPC_ADMIN_ADDRESS);
        mpcManager.createGroup(pubKeys12, 9);
        vm.prank(MPC_ADMIN_ADDRESS);
        mpcManager.requestKeygen(MPC_BIG_GROUP_ID);

        bytes[] memory participants = mpcManager.getGroup(MPC_BIG_GROUP_ID);
        assertEq0(pubKeys12[0], participants[0]);
        assertEq0(pubKeys12[1], participants[1]);
        assertEq0(pubKeys12[2], participants[2]);

        vm.prank(MPC_BIG_P01_ADDRESS);
        mpcManager.reportGeneratedKey(MPC_BIG_P01_ID, MPC_GENERATED_PUBKEY);
        vm.prank(MPC_BIG_P02_ADDRESS);
        mpcManager.reportGeneratedKey(MPC_BIG_P02_ID, MPC_GENERATED_PUBKEY);
        vm.prank(MPC_BIG_P03_ADDRESS);
        mpcManager.reportGeneratedKey(MPC_BIG_P03_ID, MPC_GENERATED_PUBKEY);
        vm.prank(MPC_BIG_P04_ADDRESS);
        mpcManager.reportGeneratedKey(MPC_BIG_P04_ID, MPC_GENERATED_PUBKEY);
        vm.prank(MPC_BIG_P05_ADDRESS);
        mpcManager.reportGeneratedKey(MPC_BIG_P05_ID, MPC_GENERATED_PUBKEY);
        vm.prank(MPC_BIG_P06_ADDRESS);
        mpcManager.reportGeneratedKey(MPC_BIG_P06_ID, MPC_GENERATED_PUBKEY);
        vm.prank(MPC_BIG_P07_ADDRESS);
        mpcManager.reportGeneratedKey(MPC_BIG_P07_ID, MPC_GENERATED_PUBKEY);
        vm.prank(MPC_BIG_P08_ADDRESS);
        mpcManager.reportGeneratedKey(MPC_BIG_P08_ID, MPC_GENERATED_PUBKEY);
        vm.prank(MPC_BIG_P09_ADDRESS);
        mpcManager.reportGeneratedKey(MPC_BIG_P09_ID, MPC_GENERATED_PUBKEY);
        vm.prank(MPC_BIG_P10_ADDRESS);
        mpcManager.reportGeneratedKey(MPC_BIG_P10_ID, MPC_GENERATED_PUBKEY);
        vm.prank(MPC_BIG_P11_ADDRESS);
        mpcManager.reportGeneratedKey(MPC_BIG_P11_ID, MPC_GENERATED_PUBKEY);

        vm.expectEmit(false, false, true, true);
        emit KeyGenerated(MPC_BIG_GROUP_ID, MPC_GENERATED_PUBKEY);

        vm.prank(MPC_BIG_P12_ADDRESS);
        mpcManager.reportGeneratedKey(MPC_BIG_P12_ID, MPC_GENERATED_PUBKEY);
        assertEq(uint256(mpcManager.lastKeygenRequest()), uint256(MPC_BIG_GROUP_ID) + uint8(KeygenStatus.COMPLETED));
    }

    function testCreateGroupNotSorted() public {
        vm.prank(MPC_ADMIN_ADDRESS);
        // Invalid public key
        pubKeys[0] = MPC_PLAYER_3_PUBKEY;
        pubKeys[1] = MPC_PLAYER_1_PUBKEY;
        pubKeys[2] = MPC_PLAYER_2_PUBKEY;
        vm.expectRevert(MpcManager.PublicKeysNotSorted.selector);
        mpcManager.createGroup(pubKeys, MPC_THRESHOLD);
    }

    function testCreateGroup() public {
        // Non admin
        vm.prank(USER1_ADDRESS);
        vm.expectRevert(
            "AccessControl: account 0xd8da6bf26964af9d7eed9e03e53415d37aa96045 is missing role 0x9fece4792c7ff5d25a4f6041da7db799a6228be21fcb6358ef0b12f1dd685cb6"
        );
        mpcManager.createGroup(pubKeys, MPC_THRESHOLD);

        vm.prank(MPC_ADMIN_ADDRESS);
        // Invalid public key
        pubKeys[2] = TOO_SHORT_PUKEY;
        vm.expectRevert(MpcManager.InvalidPublicKey.selector);
        mpcManager.createGroup(pubKeys, MPC_THRESHOLD);

        // Success case
        resetParticipantPublicKeys();
        vm.prank(MPC_ADMIN_ADDRESS);
        vm.expectEmit(false, false, true, true);
        emit ParticipantAdded(MPC_PLAYER_1_PUBKEY, MPC_GROUP_ID, 1);
        emit ParticipantAdded(MPC_PLAYER_2_PUBKEY, MPC_GROUP_ID, 2);
        emit ParticipantAdded(MPC_PLAYER_3_PUBKEY, MPC_GROUP_ID, 3);
        mpcManager.createGroup(pubKeys, MPC_THRESHOLD);
    }

    function testGetGroup() public {
        setupGroup();
        bytes[] memory participants = mpcManager.getGroup(MPC_GROUP_ID);
        assertEq0(pubKeys[0], participants[0]);
        assertEq0(pubKeys[1], participants[1]);
        assertEq0(pubKeys[2], participants[2]);
    }

    function testKeygenRequest() public {
        setupGroup();

        vm.prank(MPC_ADMIN_ADDRESS);
        vm.expectEmit(false, false, true, true);
        emit KeygenRequestAdded(MPC_GROUP_ID, 1);
        mpcManager.requestKeygen(MPC_GROUP_ID);
        assertEq(uint256(mpcManager.lastKeygenRequest()), uint256(MPC_GROUP_ID) + uint8(KeygenStatus.REQUESTED));

        // Can cancel before started
        vm.prank(MPC_ADMIN_ADDRESS);
        vm.expectEmit(false, false, true, true);
        emit KeygenRequestCanceled(MPC_GROUP_ID, 1);
        mpcManager.cancelKeygen();
        assertEq(uint256(mpcManager.lastKeygenRequest()), uint256(MPC_GROUP_ID) + uint8(KeygenStatus.CANCELED));
        // Cannot report if canceled
        vm.prank(MPC_PLAYER_1_ADDRESS);
        vm.expectRevert(MpcManager.KeygenNotRequested.selector);
        mpcManager.reportGeneratedKey(MPC_PARTICIPANT1_ID, MPC_GENERATED_PUBKEY);

        // Request again
        vm.prank(MPC_ADMIN_ADDRESS);
        mpcManager.requestKeygen(MPC_GROUP_ID);

        vm.prank(MPC_PLAYER_1_ADDRESS);
        mpcManager.reportGeneratedKey(MPC_PARTICIPANT1_ID, MPC_GENERATED_PUBKEY);
        vm.prank(MPC_PLAYER_2_ADDRESS);
        mpcManager.reportGeneratedKey(MPC_PARTICIPANT2_ID, MPC_GENERATED_PUBKEY);

        // Can cancel before done
        vm.prank(MPC_ADMIN_ADDRESS);
        mpcManager.cancelKeygen();

        vm.prank(MPC_ADMIN_ADDRESS);
        mpcManager.requestKeygen(MPC_GROUP_ID);

        vm.prank(MPC_PLAYER_1_ADDRESS);
        mpcManager.reportGeneratedKey(MPC_PARTICIPANT1_ID, MPC_GENERATED_PUBKEY);
        vm.prank(MPC_PLAYER_2_ADDRESS);
        mpcManager.reportGeneratedKey(MPC_PARTICIPANT2_ID, MPC_GENERATED_PUBKEY);
        vm.prank(MPC_PLAYER_3_ADDRESS);
        mpcManager.reportGeneratedKey(MPC_PARTICIPANT3_ID, MPC_GENERATED_PUBKEY);

        // Cannot cancel after done
        vm.prank(MPC_ADMIN_ADDRESS);
        mpcManager.cancelKeygen();
    }

    function testReportGeneratedKey() public {
        setupKeygenRequest();

        // first participant reports generated key
        vm.prank(MPC_PLAYER_1_ADDRESS);
        mpcManager.reportGeneratedKey(MPC_PARTICIPANT1_ID, MPC_GENERATED_PUBKEY);

        // second participant reports generated key
        vm.prank(MPC_PLAYER_2_ADDRESS);
        mpcManager.reportGeneratedKey(MPC_PARTICIPANT2_ID, MPC_GENERATED_PUBKEY);

        // event is emitted when the last participant reports generated key
        vm.expectEmit(false, false, true, true);
        emit KeyGenerated(MPC_GROUP_ID, MPC_GENERATED_PUBKEY);

        vm.prank(MPC_PLAYER_3_ADDRESS);
        mpcManager.reportGeneratedKey(MPC_PARTICIPANT3_ID, MPC_GENERATED_PUBKEY);
        assertEq(uint256(mpcManager.lastKeygenRequest()), uint256(MPC_GROUP_ID) + uint8(KeygenStatus.COMPLETED));
    }

    function testGetKey() public {
        setupKey();
        bytes32 groupId = mpcManager.getGroupIdByKey(MPC_GENERATED_PUBKEY);
        assertEq(MPC_GROUP_ID, groupId);
    }

    function testRequestStaking() public {
        // Called by wrong sender
        vm.prank(USER1_ADDRESS);
        vm.deal(USER1_ADDRESS, STAKE_AMOUNT);
        vm.expectRevert(MpcManager.AvaLidoOnly.selector);
        mpcManager.requestStake{value: STAKE_AMOUNT}(VALIDATOR_1, STAKE_AMOUNT, STAKE_START_TIME, STAKE_END_TIME);

        // Called before keygen
        vm.prank(AVALIDO_ADDRESS);
        vm.deal(AVALIDO_ADDRESS, STAKE_AMOUNT);

        vm.expectRevert(MpcManager.KeyNotGenerated.selector);
        mpcManager.requestStake{value: STAKE_AMOUNT}(VALIDATOR_1, STAKE_AMOUNT, STAKE_START_TIME, STAKE_END_TIME);

        setupKey();

        // Called with incorrect amount
        vm.prank(AVALIDO_ADDRESS);
        vm.deal(AVALIDO_ADDRESS, STAKE_AMOUNT);
        vm.expectRevert(MpcManager.InvalidAmount.selector);
        mpcManager.requestStake{value: STAKE_AMOUNT - 1}(VALIDATOR_1, STAKE_AMOUNT, STAKE_START_TIME, STAKE_END_TIME);

        // Called with correct sender and after keygen
        vm.prank(AVALIDO_ADDRESS);
        vm.deal(AVALIDO_ADDRESS, STAKE_AMOUNT);
        vm.expectEmit(false, false, true, true);
        emit StakeRequestAdded(1, MPC_GENERATED_PUBKEY, VALIDATOR_1, STAKE_AMOUNT, STAKE_START_TIME, STAKE_END_TIME);
        mpcManager.requestStake{value: STAKE_AMOUNT}(VALIDATOR_1, STAKE_AMOUNT, STAKE_START_TIME, STAKE_END_TIME);
        assertEq(address(MPC_GENERATED_ADDRESS).balance, STAKE_AMOUNT);
    }

    function testCannotRequestStakingWhenPaused() public {
        setupKey();
        vm.prank(PAUSE_ADMIN_ADDRESS);
        mpcManager.pause();

        vm.deal(AVALIDO_ADDRESS, STAKE_AMOUNT);
        vm.prank(AVALIDO_ADDRESS);
        vm.expectRevert("Pausable: paused");
        mpcManager.requestStake{value: STAKE_AMOUNT}(VALIDATOR_1, STAKE_AMOUNT, STAKE_START_TIME, STAKE_END_TIME);

        vm.prank(PAUSE_ADMIN_ADDRESS);
        mpcManager.resume();
        vm.prank(AVALIDO_ADDRESS);
        vm.expectEmit(false, false, true, true);
        emit StakeRequestAdded(1, MPC_GENERATED_PUBKEY, VALIDATOR_1, STAKE_AMOUNT, STAKE_START_TIME, STAKE_END_TIME);
        mpcManager.requestStake{value: STAKE_AMOUNT}(VALIDATOR_1, STAKE_AMOUNT, STAKE_START_TIME, STAKE_END_TIME);
        assertEq(address(MPC_GENERATED_ADDRESS).balance, STAKE_AMOUNT);
    }

    function testJoinStakingRequest() public {
        setupStakingRequest();

        vm.prank(MPC_PLAYER_1_ADDRESS);
        mpcManager.joinRequest(MPC_PARTICIPANT1_ID, bytes32(uint256(1)));

        // Event emitted after required t+1 participants have joined
        vm.expectEmit(false, false, true, true);
        uint256 indices = INDEX_1 + INDEX_2;
        emit RequestStarted(bytes32(uint256(1)), indices);
        vm.prank(MPC_PLAYER_2_ADDRESS);
        mpcManager.joinRequest(MPC_PARTICIPANT2_ID, bytes32(uint256(1)));

        // Cannot join anymore after required t+1 participants have joined
        vm.prank(MPC_PLAYER_3_ADDRESS);
        vm.expectRevert(MpcManager.QuorumAlreadyReached.selector);
        mpcManager.joinRequest(MPC_PARTICIPANT3_ID, bytes32(uint256(1)));
    }

    function testReportRequestFailed() public {
        setupStakingRequest();

        vm.prank(MPC_PLAYER_1_ADDRESS);
        mpcManager.joinRequest(MPC_PARTICIPANT1_ID, bytes32(uint256(1)));

        bytes memory data = hex"11";

        // Cannot report failed before quorum reached
        vm.prank(MPC_PLAYER_1_ADDRESS);
        vm.expectRevert(MpcManager.QuorumNotReached.selector);
        mpcManager.reportRequestFailed(MPC_PARTICIPANT1_ID, bytes32(uint256(1)), data);

        // Quorum reached
        vm.prank(MPC_PLAYER_2_ADDRESS);
        mpcManager.joinRequest(MPC_PARTICIPANT2_ID, bytes32(uint256(1)));

        // Cannot report failed if not a member of quorum
        vm.prank(MPC_PLAYER_3_ADDRESS);
        vm.expectRevert(MpcManager.NotInQuorum.selector);
        mpcManager.reportRequestFailed(MPC_PARTICIPANT3_ID, bytes32(uint256(1)), data);

        // Can report failed after quorum reached
        vm.expectEmit(false, false, true, true);
        emit RequestFailed(bytes32(uint256(1)), data);
        vm.prank(MPC_PLAYER_1_ADDRESS);
        mpcManager.reportRequestFailed(MPC_PARTICIPANT1_ID, bytes32(uint256(1)), data);
    }

    // -------------------------------------------------------------------------
    //  Private helper functions
    // -------------------------------------------------------------------------

    function setupGroup() private {
        vm.prank(MPC_ADMIN_ADDRESS);
        mpcManager.createGroup(pubKeys, MPC_THRESHOLD);
    }

    function setupKeygenRequest() private {
        setupGroup();
        vm.prank(MPC_ADMIN_ADDRESS);
        mpcManager.requestKeygen(MPC_GROUP_ID);
    }

    function setupKey() private {
        setupKeygenRequest();
        vm.prank(MPC_PLAYER_1_ADDRESS);
        mpcManager.reportGeneratedKey(MPC_PARTICIPANT1_ID, MPC_GENERATED_PUBKEY);
        vm.prank(MPC_PLAYER_2_ADDRESS);
        mpcManager.reportGeneratedKey(MPC_PARTICIPANT2_ID, MPC_GENERATED_PUBKEY);
        vm.prank(MPC_PLAYER_3_ADDRESS);
        mpcManager.reportGeneratedKey(MPC_PARTICIPANT3_ID, MPC_GENERATED_PUBKEY);
    }

    function setupStakingRequest() private {
        setupKey();
        vm.prank(AVALIDO_ADDRESS);
        vm.deal(AVALIDO_ADDRESS, STAKE_AMOUNT);
        mpcManager.requestStake{value: STAKE_AMOUNT}(VALIDATOR_1, STAKE_AMOUNT, STAKE_START_TIME, STAKE_END_TIME);
    }
}
