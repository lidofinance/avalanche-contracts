// SPDX-FileCopyrightText: 2022 Hyperelliptic Labs and RockX
// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.10;

// Added so that slither can parse this file correctly.
interface Empty {

}

struct UnstakeRequest {
    address requester; // The user who requested the unstake.
    uint64 requestedAt; // The block.timestamp when the unstake request was made.
    uint256 amountRequested; // The amount of AVAX equal to the stAVAX the user had at request time.
    uint256 amountFilled; // The amount of free'd AVAX that has been allocated to this request.
    uint256 amountClaimed; // The amount of AVAX that has been claimed by the requester.
    uint256 stAVAXLocked; // The amount of stAVAX requested to be unstaked.
}

type Validator is uint24;

// Total 24 bits
// [ i i i i i i i i i i i i i i i i v v v v v v v v v v ]
// i = 14 bits - index of node ID in list.
// v = 10 bits - number of 'hundreds of free avax, rounded down', capped at 256

library ValidatorHelpers {
    function getNodeIndex(Validator data) public pure returns (uint256) {
        // Take the first 14 bits which represents our index.
        uint24 value = Validator.unwrap(data) & 16776192; // 111111111111110000000000
        // Shift right 10 places to align
        uint24 shifted = value >> 10;
        return uint256(shifted);
    }

    function freeSpace(Validator data) public pure returns (uint256) {
        // Take the last 10 bits. Already aligned so no need to shift.
        uint24 hundredsOfAVAX = Validator.unwrap(data) & 1023; // 000000000000001111111111
        // Multiply out into Wei
        return uint256(hundredsOfAVAX) * 100 ether;
    }

    function packValidator(uint24 nodeIndex, uint24 hundredsOfAvax) public pure returns (Validator) {
        assert(nodeIndex < 16384);
        assert(hundredsOfAvax < 1024);

        uint24 data = hundredsOfAvax;
        data = data | (nodeIndex << 10);
        return Validator.wrap(data);
    }
}

bytes32 constant LAST_BYTE_MASK = 0x00000000000000000000000000000000000000000000000000000000000000ff;
bytes32 constant INIT_31_BYTE_MASK = 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff00;

// First 232 bits = Hash(PublicKeys), Next 8 bits = groupSize, Next 8 bits = threshold, Last 8 bits = party index
library IdHelpers {
    uint256 constant GROUP_SIZE_SHIFT = 16;
    uint256 constant THRESHOLD_SHIFT = 8;
    bytes32 constant GROUP_HASH_MASK = 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffff000000;

    function makeGroupId(
        bytes32 groupHash,
        uint256 groupSize,
        uint256 threshold
    ) public pure returns (bytes32) {
        assert(groupSize <= type(uint8).max);
        assert(threshold <= type(uint8).max);
        return
            (groupHash & GROUP_HASH_MASK) |
            (bytes32(groupSize) << GROUP_SIZE_SHIFT) |
            (bytes32(threshold) << THRESHOLD_SHIFT);
    }

    function makeParticipantId(bytes32 groupId, uint256 participantIndex) public pure returns (bytes32) {
        assert(participantIndex <= type(uint8).max);
        return groupId | (bytes32(participantIndex));
    }

    function getGroupSize(bytes32 groupOrParticipantId) public pure returns (uint8) {
        return uint8(uint256((groupOrParticipantId >> GROUP_SIZE_SHIFT) & LAST_BYTE_MASK));
    }

    function getThreshold(bytes32 groupOrParticipantId) public pure returns (uint8) {
        return uint8(uint256((groupOrParticipantId >> THRESHOLD_SHIFT) & LAST_BYTE_MASK));
    }

    function getGroupId(bytes32 participantId) public pure returns (bytes32) {
        return participantId & INIT_31_BYTE_MASK;
    }

    function getParticipantIndex(bytes32 participantId) public pure returns (uint8) {
        return uint8(uint256(participantId & LAST_BYTE_MASK));
    }
}

// The first byte represent the status of the request.
// The next 22 bytes are currently not used.
// The next 8 bytes bytes (64 bits) are used to represent the confirmation of max. 64 members,
// i.e. when the first bit set to 1, it means participant 1 has confirmed.
// The last byte records the number participants that have confirmed.
library RequestRecordHelpers {
    uint256 constant INIT_INDEX_BIT = 0x800000000000000000;
    bytes32 constant INDICES_MASK = bytes32(uint256(0xffffffffffffffff00));
    uint256 constant QUORUM_REACHED = 0x0100000000000000000000000000000000000000000000000000000000000000;
    uint256 constant FAILED = 0x0200000000000000000000000000000000000000000000000000000000000000;

    function makeRecord(uint256 indices, uint8 confirmationCount) public pure returns (uint256) {
        assert(indices & uint256(LAST_BYTE_MASK) == 0);
        return indices | confirmationCount;
    }

    function getIndices(uint256 record) public pure returns (uint256) {
        return record & uint256(INDICES_MASK);
    }

    function getConfirmationCount(uint256 record) public pure returns (uint8) {
        return uint8(record & uint256(LAST_BYTE_MASK));
    }

    function confirm(uint8 myIndex) public pure returns (uint256) {
        return INIT_INDEX_BIT >> (myIndex - 1); // Set bit representing my confirm.
    }

    function setQuorumReached(uint256 record) public pure returns (uint256) {
        return record | QUORUM_REACHED;
    }

    function setFailed(uint256 record) public pure returns (uint256) {
        return record | FAILED;
    }

    function isQuorumReached(uint256 record) public pure returns (bool) {
        return (record & QUORUM_REACHED) > 0;
    }

    function isFailed(uint256 record) public pure returns (bool) {
        return (record & FAILED) > 0;
    }
}

// The first 31 bytes (248 bits) is the groupId, the last byte is the status.
library KeygenStatusHelpers {
    function makeKeygenRequest(bytes32 groupId, uint8 keygenStatus) public pure returns (bytes32) {
        return (groupId & INIT_31_BYTE_MASK) | bytes32(uint256(keygenStatus));
    }

    function getGroupId(bytes32 keygenRequest) public pure returns (bytes32) {
        return keygenRequest & INIT_31_BYTE_MASK;
    }

    function getKeygenStatus(bytes32 keygenRequest) public pure returns (uint8) {
        return uint8(uint256(keygenRequest & LAST_BYTE_MASK));
    }
}
