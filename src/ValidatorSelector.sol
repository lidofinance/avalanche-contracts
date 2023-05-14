// SPDX-FileCopyrightText: 2022 Hyperelliptic Labs and RockX
// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.10;

import "openzeppelin-contracts/contracts/access/AccessControlEnumerable.sol";
import "openzeppelin-contracts/contracts/utils/math/Math.sol";
import "openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";

import "./Roles.sol";
import "./Types.sol";
import "./interfaces/IOracle.sol";

/**
 * @title Lido on Avalanche Validator Selector
 * @dev This contract helps select validators from the Oracle for staking.
 */
contract ValidatorSelector is Initializable, AccessControlEnumerable {
    // Errors
    error InvalidAddress();

    // Events
    event MaxChunkSizeChanged(uint256 newMaxChunkSize);
    event OracleAddressChanged(address newOracleAddress);
    event SmallStakeThresholdChanged(uint256 newSmallStakeThreshold);

    uint256 public smallStakeThreshold;
    uint256 public maxChunkSize;

    IOracle public oracle;

    function initialize(address oracleAddress) public initializer {
        // Roles
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setupRole(ROLE_VALIDATOR_MANAGER, msg.sender);

        // Initialize contract variables
        smallStakeThreshold = 100 ether;
        maxChunkSize = 1000 ether;
        oracle = IOracle(oracleAddress);
    }

    /**
     * @notice Select valdators to dsitribute stake to. You should not need to call this function.
     * @dev This selects the validators to distribute stake to. It is called by the Lido contract
     * when we want to allocate a stake to validators.
     * In general, our aim is to maintain decentralisation of stake across many validator nodes.
     * Assuming that we end up handling a significant proportion of total stake in the network,
     * we want to a pseudo-even distribution of stake across all validators.
     * To be pragmatic, we use a greatly simplified option for small stakes where we just allocate
     * everything to a single pseudo-random validator.
     * For larger stakes, we use a packing-esque algorithm to allocate multiple validators a portion
     * of the total stake.
     * @param amount The amount of stake to distribute.
     * @return validators The validator node ids to distribute the stake to.
     * @return allocations The amount of AVAX to allocate to each validator
     * @return remainder The remaining stake which could not be allocated.
     */
    function selectValidatorsForStake(uint256 amount)
        public
        view
        returns (
            string[] memory,
            uint256[] memory,
            uint256
        )
    {
        if (amount == 0) return (new string[](0), new uint256[](0), 0);

        Validator[] memory validators = getAvailableValidatorsWithCapacity(smallStakeThreshold);

        // We have no nodes with capacity, don't do anything.
        if (validators.length == 0) {
            return (new string[](0), new uint256[](0), amount);
        }

        uint256 startIndex = pseudoRandomIndex(validators.length);

        // For cases where we're staking < 100, we just shove everything on one pseudo-random node.
        // This is significantly simpler and cheaper than spreading it out, and 100 will not be enough
        // to skew the distribution across the network.
        if (amount <= smallStakeThreshold) {
            string[] memory vals = new string[](1);
            vals[0] = oracle.nodeIdByValidatorIndex(ValidatorHelpers.getNodeIndex(validators[startIndex]));
            uint256[] memory amounts = new uint256[](1);
            amounts[0] = amount;
            return (vals, amounts, 0);
        }

        // Compute the total free space so that we can tell if we're not going to be able to stake everything
        // right now.
        uint256 totalFreeSpace = 0;
        uint256[] memory freeSpaces = new uint256[](validators.length);
        for (uint256 index = 0; index < validators.length; index++) {
            uint256 free = ValidatorHelpers.freeSpace(validators[index]);
            totalFreeSpace += free;
            freeSpaces[index] = free;
        }

        // If we have too much to stake, recompute the amount that we _can_ stake.
        // Keep track of the remaining value to return back to the caller.
        uint256 remainingUnstaked = 0;
        if (totalFreeSpace < amount) {
            remainingUnstaked = amount - totalFreeSpace;
            amount = totalFreeSpace;
        }

        // For larger amounts, we chunk it into N pieces.
        // We then continue to pack validators with each of those chunks in a round-robin
        // fashion, until we have nothing left to stake.
        uint256 chunkSize = Math.min(amount, maxChunkSize);

        // Because we need to create a fixed size array, we use every validator, and we set the amount to 0
        // if we can't stake anything on it. Callers must check this when using the result.
        uint256[] memory resultAmounts = new uint256[](validators.length);

        // Keep track of the amount we've staked
        uint256 n = startIndex;
        uint256 amountStaked = 0;
        while (amountStaked < amount) {
            uint256 remaining = amount - amountStaked;

            // Our actual fillable space is the initial free space, minus anything already allocated.
            uint256 freeSpace = freeSpaces[n] - resultAmounts[n];

            // Stake the smallest of (total remaining, space for this node, or 1 chunk).
            uint256 amountToStake = Math.min(remaining, Math.min(freeSpace, chunkSize));

            resultAmounts[n] += amountToStake;
            amountStaked += amountToStake;

            // Move on, and loop back to the start.
            n++;
            if (n > validators.length - 1) {
                n = 0;
            }
        }

        // Build a list of IDs in line with the amounts (as the order is not guaranteed to be stable
        // across transactions)
        string[] memory validatorIds = new string[](validators.length);
        for (uint256 i = 0; i < validators.length; i++) {
            // Don't make the call to get the node index if there's no value on that node.
            if (resultAmounts[i] == 0) {
                continue;
            }
            validatorIds[i] = oracle.nodeIdByValidatorIndex(ValidatorHelpers.getNodeIndex(validators[i]));
        }

        return (validatorIds, resultAmounts, remainingUnstaked);
    }

    function pseudoRandomIndex(uint256 length) internal view returns (uint256) {
        return uint256(keccak256(abi.encodePacked(block.timestamp))) % length;
    }

    /**
     * @notice Gets the validators which have capacity to handle the given amount of AVAX.
     * @dev Returns an dynamic array of validators.
     * @param amount The amount of AVAX to allocate in total.
     * @return validators The validators which have capacity to handle the given amount of AVAX.
     */
    function getAvailableValidatorsWithCapacity(uint256 amount) public view returns (Validator[] memory) {
        // 1. Fetch our validators from the Oracle
        Validator[] memory validators = oracle.getLatestValidators();

        // 2. Count how many validators meet our criteria
        uint256 countOfSuitableValidators = 0;
        for (uint256 index = 0; index < validators.length; index++) {
            if (ValidatorHelpers.freeSpace(validators[index]) < amount) {
                continue;
            }
            countOfSuitableValidators++;
        }

        if (countOfSuitableValidators == 0) {
            return new Validator[](0);
        }

        // 3. Compress the array into just suitable validators
        Validator[] memory result = new Validator[](countOfSuitableValidators);
        uint256 resultIndexCount = 0;
        for (uint256 index = 0; index < validators.length; index++) {
            if (ValidatorHelpers.freeSpace(validators[index]) < amount) {
                continue;
            }
            result[resultIndexCount] = validators[index];
            resultIndexCount++;
        }
        return result;
    }

    // -------------------------------------------------------------------------
    //  Role-based functions
    // -------------------------------------------------------------------------

    function setOracleAddress(address oracleAddress) public onlyRole(ROLE_VALIDATOR_MANAGER) {
        if (oracleAddress == address(0)) revert InvalidAddress();

        oracle = IOracle(oracleAddress);

        emit OracleAddressChanged(oracleAddress);
    }

    function setSmallStakeThreshold(uint256 _smallStakeThreshold) external onlyRole(ROLE_VALIDATOR_MANAGER) {
        smallStakeThreshold = _smallStakeThreshold;

        emit SmallStakeThresholdChanged(_smallStakeThreshold);
    }

    function setMaxChunkSize(uint256 _maxChunkSize) external onlyRole(ROLE_VALIDATOR_MANAGER) {
        maxChunkSize = _maxChunkSize;

        emit MaxChunkSizeChanged(_maxChunkSize);
    }
}
