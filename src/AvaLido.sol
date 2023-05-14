// SPDX-FileCopyrightText: 2022 Hyperelliptic Labs and RockX
// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.10;

/*
 █████╗ ██╗   ██╗ █████╗ ██╗     ██╗██████╗  ██████╗
██╔══██╗██║   ██║██╔══██╗██║     ██║██╔══██╗██╔═══██╗
███████║██║   ██║███████║██║     ██║██║  ██║██║   ██║
██╔══██║╚██╗ ██╔╝██╔══██║██║     ██║██║  ██║██║   ██║
██║  ██║ ╚████╔╝ ██║  ██║███████╗██║██████╔╝╚██████╔╝
╚═╝  ╚═╝  ╚═══╝  ╚═╝  ╚═╝╚══════╝╚═╝╚═════╝  ╚═════╝

                         ,██▄
                        /█████
                       ████████
                      ████████
                    ,████████   ,,
                   ▄████████   ████
                  ████████    ██████
                 ████████    ████████

              ████                 ,███
             ████████▌         ,████████
             ████████████,  █████████████
            ]████████████████████████████
             ████████████████████████████
             ███████████████████████████▌
              ██████████████████████████
               ███████████████████████
                 ███████████████████
                    ╙████████████
*/

import "openzeppelin-contracts/contracts/security/Pausable.sol";
import "openzeppelin-contracts/contracts/security/ReentrancyGuard.sol";
import "openzeppelin-contracts/contracts/access/AccessControlEnumerable.sol";
import "openzeppelin-contracts/contracts/utils/math/Math.sol";
import "openzeppelin-contracts/contracts/finance/PaymentSplitter.sol";
import "openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";

import "./Types.sol";
import "./Roles.sol";
import "./stAVAX.sol";
import "./interfaces/IValidatorSelector.sol";
import "./interfaces/IMpcManager.sol";
import "./interfaces/ITreasury.sol";
import "./interfaces/ITreasuryBeneficiary.sol";

/**
 * @title Lido on Avalanche
 * @author Hyperelliptic Labs and RockX
 */
contract AvaLido is ITreasuryBeneficiary, Pausable, ReentrancyGuard, stAVAX, AccessControlEnumerable {
    // Errors
    error TreasuryOnly();
    error InvalidStakeAmount();
    error ProtocolStakedAmountTooLarge();
    error TooManyConcurrentUnstakeRequests();
    error NotAuthorized();
    error ClaimTooLarge();
    error ClaimTooSoon(uint64 availableAt);
    error InsufficientBalance();
    error NoAvailableValidators();
    error InvalidAddress();
    error InvalidConfiguration();
    error TransferFailed();

    // Events
    event DepositEvent(address indexed from, uint256 amount, address referral);
    event WithdrawRequestSubmittedEvent(
        address indexed from,
        uint256 avaxAmount,
        uint256 stAvaxAmount,
        uint256 requestIndex
    );
    event RequestFullyFilledEvent(uint256 requestedAmount, uint256 indexed requestIndex);
    event RequestPartiallyFilledEvent(uint256 fillAmount, uint256 indexed requestIndex);
    event ClaimEvent(address indexed from, uint256 claimAmount, bool indexed finalClaim, uint256 indexed requestIndex);
    event RewardsCollectedEvent(uint256 amount);
    event ProtocolFeeEvent(uint256 amount);
    event ProtocolConfigChanged(string indexed eventNameHash, string eventName, bytes data);

    // State variables

    // The array of all unstake requests. This acts as a queue, and we maintain a separate pointer
    // to point to the head of the queue rather than removing state from the array. This allows us to:
    // - maintain an immutable order of requests.
    // - find the next requests to fill in constant time.
    UnstakeRequest[] public unstakeRequests;

    // Pointer to the head of the unfilled section of the queue.
    uint256 private unfilledHead;

    // Tracks the amount of AVAX being staked. Also includes AVAX pending staking or unstaking.
    uint256 public amountStakedAVAX;

    // Track the amount of AVAX in the contract which is waiting to be staked.
    // When the stake is triggered, this amount will be sent to the MPC system.
    uint256 public amountPendingStakeAVAX;

    // Track the amount of AVAX in the contract which is waiting to fill unstake requests,
    // in the case where this has been limited to prevent unstake flooding.
    uint256 public amountPendingUnstakeFillsAVAX;

    // Record the number of unstake requests per user so that we can limit them to our max.
    mapping(address => uint8) public unstakeRequestCount;

    // Protocol fee is expressed as basis points (BPS). One BPS is 1/100 of 1%.
    uint256 public protocolFeeBasisPoints;

    // Addresses which protocol fees are sent to.
    // Protocol fee split is set out in the "Lido for Avalance" proposal:
    // https://research.lido.fi/t/lido-for-avalanche-joint-proposal-by-hyperelliptic-labs-and-rockx/1610
    PaymentSplitter public protocolFeeSplitter;

    // For gas efficiency, we won't emit staking events if the pending amount is below this value.
    uint256 public minStakeBatchAmount;

    // Smallest amount a user can stake.
    uint256 public minStakeAmountAVAX;

    // Smallest amount a user can unstake.
    uint256 public minUnstakeAmountStAVAX;

    // Period over which AVAX is staked.
    uint256 public stakePeriod;

    // Control in the case that we want to slow rollout.
    uint256 public maxProtocolControlledAVAX;

    // Maximum unstake requests a user can open at once (prevents spamming).
    uint8 public maxUnstakeRequests;

    // Time that an unstaker must wait before being able to claim.
    uint64 public minimumClaimWaitTimeSeconds;

    // Track the total AVAX buffered on this contract.
    // Access via the `bufferedBalance` function.
    uint256 private _bufferedBalance;

    // The buffer added to account for delay in exporting to P-chain
    uint256 pChainExportBuffer;

    // Number of times we loop through unstake requests when filling
    uint256 unstakeLoopBound;

    // Selector used to find validators to stake on.
    IValidatorSelector public validatorSelector;

    // Address where we'll send AVAX to be staked.
    address private mpcManagerAddress;
    IMpcManager public mpcManager;
    ITreasury public principalTreasury;
    ITreasury public rewardTreasury;

    function initialize(
        address lidoFeeAddress,
        address authorFeeAddress,
        address validatorSelectorAddress,
        address _mpcManagerAddress
    ) public initializer {
        __ERC20_init("Staked AVAX", "stAVAX");

        // Roles
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setupRole(ROLE_PAUSE_MANAGER, msg.sender);
        _setupRole(ROLE_RESUME_MANAGER, msg.sender);
        _setupRole(ROLE_FEE_MANAGER, msg.sender);
        _setupRole(ROLE_TREASURY_MANAGER, msg.sender);
        _setupRole(ROLE_MPC_MANAGER, msg.sender);
        _setupRole(ROLE_PROTOCOL_MANAGER, msg.sender);

        // Initialize contract variables.
        protocolFeeBasisPoints = 1000; // 1000 BPS = 10%
        minStakeBatchAmount = 10 ether;
        minStakeAmountAVAX = 0.1 ether;
        minUnstakeAmountStAVAX = 0.05 ether;
        stakePeriod = 14 days;
        maxUnstakeRequests = 10;
        maxProtocolControlledAVAX = 100_000 ether; // Initial limit for deploy.
        pChainExportBuffer = 1 hours;
        minimumClaimWaitTimeSeconds = 3600;
        unstakeLoopBound = 100;

        mpcManager = IMpcManager(_mpcManagerAddress);
        validatorSelector = IValidatorSelector(validatorSelectorAddress);

        // Initial payment addresses and fee split.
        address[] memory paymentAddresses = new address[](2);
        paymentAddresses[0] = lidoFeeAddress;
        paymentAddresses[1] = authorFeeAddress;

        uint256[] memory paymentSplit = new uint256[](2);
        paymentSplit[0] = 80_000;
        paymentSplit[1] = 20_000;

        setProtocolFeeSplit(paymentAddresses, paymentSplit);
    }

    // -------------------------------------------------------------------------
    //  Public functions
    // -------------------------------------------------------------------------

    /**
     * @notice Return your stAVAX to create an unstake request.
     * @dev We limit users to some maximum number of concurrent unstake requests to prevent
     * people flooding the queue. The amount for each unstake request is unbounded.
     * @param stAVAXAmount The amount of stAVAX to unstake.
     * @return An unstake request ID for use when claiming AVAX.
     */
    function requestWithdrawal(uint256 stAVAXAmount) external whenNotPaused nonReentrant returns (uint256) {
        if (stAVAXAmount < minUnstakeAmountStAVAX) revert InvalidStakeAmount();

        if (unstakeRequestCount[msg.sender] >= maxUnstakeRequests) {
            revert TooManyConcurrentUnstakeRequests();
        }
        unstakeRequestCount[msg.sender]++;

        if (balanceOf(msg.sender) < stAVAXAmount) {
            revert InsufficientBalance();
        }

        // Transfer stAVAX from user to our contract.
        _transfer(msg.sender, address(this), stAVAXAmount);
        uint256 avaxAmount = stAVAXToAVAX(protocolControlledAVAX(), stAVAXAmount);

        // Create the request and store in our queue.
        unstakeRequests.push(UnstakeRequest(msg.sender, uint64(block.timestamp), avaxAmount, 0, 0, stAVAXAmount));

        uint256 requestIndex = unstakeRequests.length - 1;
        emit WithdrawRequestSubmittedEvent(msg.sender, avaxAmount, stAVAXAmount, requestIndex);

        return requestIndex;
    }

    /**
     * @notice Look up an unstake request by index in the queue.
     * @dev As the queue is append-only, we can simply return the request at the given index.
     * @param requestIndex index The index of the request to look up.
     * @return UnstakeRequest The request at the given index.
     */
    function requestByIndex(uint256 requestIndex) public view returns (UnstakeRequest memory) {
        return unstakeRequests[requestIndex];
    }

    /**
     * @notice Claim your AVAX from a completed unstake requested.
     * @dev This allows users to claim their AVAX back. We burn the stAVAX that we've been holding
     * at this point.
     * Note that we also allow partial claims of unstake requests so that users don't need to wait
     * for the entire request to be filled to get some liquidity. This is one of the reasons we set the
     * exchange rate in requestWithdrawal instead of at claim time. (The other is so that unstakers don't
     * earn rewards).
     */
    function claim(uint256 requestIndex, uint256 amountAVAX) external whenNotPaused nonReentrant {
        UnstakeRequest memory request = requestByIndex(requestIndex);

        if (request.requester != msg.sender) revert NotAuthorized();
        if (amountAVAX > request.amountFilled - request.amountClaimed) revert ClaimTooLarge();
        if (amountAVAX > bufferedBalance()) revert InsufficientBalance();

        uint64 availableAt = request.requestedAt + minimumClaimWaitTimeSeconds;
        if (block.timestamp < availableAt) revert ClaimTooSoon({availableAt: availableAt});

        // Partial claim, update amounts.
        request.amountClaimed += amountAVAX;
        // To save gas we only update the mapping on partial claims.
        // We delete full claims at the end of the function.
        if (!isFullyClaimed(request)) {
            unstakeRequests[requestIndex] = request;
        }

        // Burn the stAVAX in the UnstakeRequest. If it's a partial claim we need to burn a proportional amount
        // of the original stAVAX using the stAVAX and AVAX amounts in the unstake request.
        uint256 amountOfStAVAXToBurn = Math.mulDiv(request.stAVAXLocked, amountAVAX, request.amountRequested);

        // In the case that a user claims all but one wei of their avax, and then claims 1 wei separately, we
        // will incorrectly round down the amount of stAVAX to burn, leading to a left over amount of 1 wei stAVAX
        // in the contract, and a request which can never be fully claimed. I don't know why anyone would do this,
        // but maybe this will keep our internal accounting more in order.
        if (amountOfStAVAXToBurn == 0) {
            amountOfStAVAXToBurn = 1;
        }
        _burn(address(this), amountOfStAVAXToBurn);

        // Track buffered balance.
        _bufferedBalance -= amountAVAX;

        // Emit claim event.
        bool fullyClaimed = isFullyClaimed(request);
        if (fullyClaimed) {
            // Final claim, remove this request so that it can't be claimed again.
            // Note, this doesn't alter the indicies of the other requests.
            unstakeRequestCount[msg.sender]--;
            delete unstakeRequests[requestIndex];
        }

        // Emit an event which describes the partial claim.
        emit ClaimEvent(msg.sender, amountAVAX, fullyClaimed, requestIndex);

        // Transfer the AVAX to the user
        (bool success, ) = msg.sender.call{value: amountAVAX}("");
        if (!success) revert TransferFailed();
    }

    /**
     * @notice Calculate the amount of AVAX controlled by the protocol.
     * @dev This is the amount of AVAX staked (or technically pending being staked),
     * plus the amount of AVAX that is in the contract. This _does_ include the AVAX
     * in the contract which has been allocated to unstake requests, but not yet claimed,
     * because we don't burn stAVAX until the claim happens.
     * *This should always be >= the total supply of stAVAX*.
     */
    function protocolControlledAVAX() public view override returns (uint256) {
        return amountStakedAVAX + bufferedBalance();
    }

    /**
     * @notice Initiate execution of staking for all pending AVAX.
     * @return uint256 The amount of AVAX that was staked.
     * @dev This function takes all pending AVAX and attempts to allocate it to validators.
     * The funds are then transferred to the MPC system for cross-chain transport and staking.
     * Note that this function is publicly available, meaning anyone can pay gas to initiate the
     * staking operation and we don't require any special permissions.
     * It would be sensible for our team to also call this at a regular interval.
     */
    function initiateStake() external whenNotPaused nonReentrant returns (uint256) {
        if (amountPendingStakeAVAX == 0 || amountPendingStakeAVAX < minStakeBatchAmount) {
            return 0;
        }

        (string[] memory ids, uint256[] memory amounts, uint256 remaining) = validatorSelector.selectValidatorsForStake(
            amountPendingStakeAVAX
        );

        if (ids.length == 0 || amounts.length == 0) revert NoAvailableValidators();

        uint256 totalToStake = amountPendingStakeAVAX - remaining;

        amountStakedAVAX += totalToStake;

        // Our pending AVAX is now whatever we couldn't allocate.
        amountPendingStakeAVAX = remaining;

        // Add some buffer to account for delay in exporting to P-chain and MPC consensus.
        uint256 startTime = block.timestamp + pChainExportBuffer;
        uint256 endTime = startTime + stakePeriod;
        for (uint256 i = 0; i < ids.length; i++) {
            uint256 amount = amounts[i];

            // The array from selectValidatorsForStake may be sparse, so we need to ignore any validators
            // which are set with 0 amounts.
            if (amount == 0) {
                continue;
            }
            mpcManager.requestStake{value: amount}(ids[i], amount, startTime, endTime);

            // Track buffered balance.
            _bufferedBalance -= amount;
        }

        return totalToStake;
    }

    // -------------------------------------------------------------------------
    //  Payable functions
    // -------------------------------------------------------------------------

    /**
     * @notice Deposit your AVAX to receive Staked AVAX (stAVAX) in return.
     * @dev Receives AVAX and mints StAVAX to msg.sender.
     * @param referral Address of referral.
     */
    function deposit(address referral) external payable whenNotPaused nonReentrant {
        uint256 amount = msg.value;
        if (amount < minStakeAmountAVAX) revert InvalidStakeAmount();
        if (protocolControlledAVAX() + amount > maxProtocolControlledAVAX) revert ProtocolStakedAmountTooLarge();

        // Track buffered balance.
        _bufferedBalance += amount;

        // Mint stAVAX for user at the currently calculated exchange rate
        // We don't want to count this deposit in protocolControlledAVAX()
        uint256 amountOfStAVAXToMint = avaxToStAVAX(protocolControlledAVAX() - amount, amount);
        _mint(msg.sender, amountOfStAVAXToMint);

        emit DepositEvent(msg.sender, amount, referral);

        // Take the amount and stash it to be staked at a later time.
        // Note that we explicitly do not subsequently use this pending amount to fill unstake requests.
        // This intentionally removes the ability to instantly stake and unstake, which makes the
        // arb opportunity around trying to collect reward value significantly riskier/impractical.
        amountPendingStakeAVAX += amount;
    }

    function receiveFund() external payable {
        if (msg.sender != address(principalTreasury) && msg.sender != address(rewardTreasury)) revert TreasuryOnly();
    }

    /**
     * @notice Claims the value in treasury.
     * @dev Claims AVAX from the MPC wallet and uses it to fill unstake requests.
     * Any remaining funds after all requests are filled are re-staked.
     */
    function claimUnstakedPrincipals() external {
        if (amountStakedAVAX == 0) revert InvalidStakeAmount();

        uint256 principalBalance = address(principalTreasury).balance;
        if (principalBalance == 0) return;

        // Claim up to a maximum of the amount staked.
        // This defends against the treasury balance being larger than the amount staked
        // which could happen if people send money to the treasury directly.
        uint256 amountToClaim = Math.min(principalBalance, amountStakedAVAX);

        // Track buffered balance and claim.
        _bufferedBalance += amountToClaim;
        principalTreasury.claim(amountToClaim);

        // We received this from an unstake, so remove from our count.
        // Anything restaked will be counted again on the way out.
        // Note: This avoids double counting, as the total count includes AVAX held by
        // the contract.
        amountStakedAVAX -= amountToClaim;

        // Fill unstake requests and allocate excess for restaking.
        fillUnstakeRequests(amountToClaim);
    }

    /**
     * @notice Claims the value in treasury and distribute.
     * @dev this function takes the protocol fee from the rewards, distributes
     * it to the protocol fee splitters, and then retains the rest.
     * We then kick off our stAVAX rebase.
     */
    function claimRewards() external {
        uint256 val = address(rewardTreasury).balance;
        if (val == 0) return;

        // Track buffered balance and claim.
        _bufferedBalance += val;
        rewardTreasury.claim(val);

        // Caclulate protocol fee.
        uint256 protocolFee = Math.mulDiv(val, protocolFeeBasisPoints, 10_000);

        // Track buffered balance and transfer fee.
        _bufferedBalance -= protocolFee;
        payable(protocolFeeSplitter).transfer(protocolFee);

        emit ProtocolFeeEvent(protocolFee);

        uint256 afterFee = val - protocolFee;
        emit RewardsCollectedEvent(afterFee);

        // Fill unstake requests and allocate excess for restaking.
        fillUnstakeRequests(afterFee);
    }

    // -------------------------------------------------------------------------
    //  Private/internal functions
    // -------------------------------------------------------------------------

    /**
     * @dev Gets the total AVAX buffered on this contract.
     */
    function bufferedBalance() public view returns (uint256) {
        assert(address(this).balance >= _bufferedBalance);
        return _bufferedBalance;
    }

    /**
     * @dev Gets unaccounted (excess) AVAX on this contract balance.
     */
    function unaccountedBalance() external view returns (uint256) {
        return address(this).balance - bufferedBalance();
    }

    /**
     * @dev Wraps `_fillUnstakeRequests` and tracks the amount of AVAX in the
     * contract which is pending unstake fills to prevent unstake flooding.
     * @param amount The amount of free'd AVAX made available to fill requests.
     */
    function fillUnstakeRequests(uint256 amount) private {
        (bool completed, uint256 remaining) = _fillUnstakeRequests(amountPendingUnstakeFillsAVAX + amount);

        if (!completed) {
            amountPendingUnstakeFillsAVAX = remaining;
            return;
        }

        // Take the remaining amount and stash it to be staked at a later time.
        // Note that we explicitly do not subsequently use this pending amount to fill unstake requests.
        // This intentionally removes the ability to instantly stake and unstake, which makes the
        // arb opportunity around trying to collect rewards value significantly riskier/impractical.
        amountPendingStakeAVAX += remaining;
        amountPendingUnstakeFillsAVAX = 0;
    }

    /**
     * @dev Fills the next available unstake request with the given amount.
     * This function works by reading the `unstakeRequests` queue, in-order, starting
     * from the `unfilledHead` pointer. When a request is completely filled, we update
     * the `unfilledHead` pointer to the next request.
     * Note that filled requests are not removed from the queue, as they still must be
     * claimed by users.
     * @param inputAmount The amount of free'd AVAX made available to fill requests.
     * @return bool Whether the queue has been completely cleared.
     * @return uint256 The amount of AVAX that is left over after filling requests.
     */
    function _fillUnstakeRequests(uint256 inputAmount) private returns (bool, uint256) {
        // Queue unchecked so returns incomplete.
        if (inputAmount == 0) return (false, 0);

        uint256 amountFilled = 0;
        uint256 numberFilled = 0;
        uint256 remaining = inputAmount;

        // Assumes order of the array is creation order.
        for (uint256 i = unfilledHead; i < unstakeRequests.length; i++) {
            if (remaining == 0) {
                return (false, 0);
            }

            // Return early to prevent unstake flooding
            if (numberFilled == unstakeLoopBound) {
                return (false, remaining);
            }

            uint256 amountRequired = unstakeRequests[i].amountRequested - unstakeRequests[i].amountFilled;

            uint256 amountToFill = Math.min(amountRequired, remaining);
            amountFilled += amountToFill;

            unstakeRequests[i].amountFilled += amountToFill;

            // We filled the request entirely, so move the head pointer on
            if (isFilled(unstakeRequests[i])) {
                unfilledHead = i + 1;
                emit RequestFullyFilledEvent(unstakeRequests[i].amountRequested, i);
            } else {
                emit RequestPartiallyFilledEvent(amountToFill, i);
            }

            remaining = inputAmount - amountFilled;
            numberFilled++;
        }
        return (true, remaining);
    }

    function isFilled(UnstakeRequest memory request) private pure returns (bool) {
        return request.amountFilled >= request.amountRequested;
    }

    function isFullyClaimed(UnstakeRequest memory request) private pure returns (bool) {
        return request.amountClaimed >= request.amountRequested;
    }

    function exchangeRateAVAXToStAVAX() external view returns (uint256) {
        return avaxToStAVAX(protocolControlledAVAX(), 1 ether);
    }

    function exchangeRateStAVAXToAVAX() external view returns (uint256) {
        return stAVAXToAVAX(protocolControlledAVAX(), 1 ether);
    }

    // -------------------------------------------------------------------------
    //  Admin functions
    // -------------------------------------------------------------------------

    function pause() external onlyRole(ROLE_PAUSE_MANAGER) {
        _pause();
    }

    function resume() external onlyRole(ROLE_RESUME_MANAGER) {
        _unpause();
    }

    function setProtocolFeeBasisPoints(uint256 _protocolFeeBasisPoints) external onlyRole(ROLE_FEE_MANAGER) {
        require(_protocolFeeBasisPoints <= 10_000);
        protocolFeeBasisPoints = _protocolFeeBasisPoints;

        emit ProtocolConfigChanged(
            "setProtocolFeeBasisPoints",
            "setProtocolFeeBasisPoints",
            abi.encode(_protocolFeeBasisPoints)
        );
    }

    function setPrincipalTreasuryAddress(address _address) external onlyRole(ROLE_TREASURY_MANAGER) {
        if (_address == address(0)) revert InvalidAddress();

        principalTreasury = ITreasury(_address);

        emit ProtocolConfigChanged("setPrincipalTreasuryAddress", "setPrincipalTreasuryAddress", abi.encode(_address));
    }

    function setRewardTreasuryAddress(address _address) external onlyRole(ROLE_TREASURY_MANAGER) {
        if (_address == address(0)) revert InvalidAddress();

        rewardTreasury = ITreasury(_address);

        emit ProtocolConfigChanged("setRewardTreasuryAddress", "setRewardTreasuryAddress", abi.encode(_address));
    }

    function setProtocolFeeSplit(address[] memory paymentAddresses, uint256[] memory paymentSplit)
        public
        onlyRole(ROLE_TREASURY_MANAGER)
    {
        protocolFeeSplitter = new PaymentSplitter(paymentAddresses, paymentSplit);

        emit ProtocolConfigChanged(
            "setProtocolFeeSplit",
            "setProtocolFeeSplit",
            abi.encode(paymentAddresses, paymentSplit)
        );
    }

    function setMinStakeBatchAmount(uint256 _minStakeBatchAmount) external onlyRole(ROLE_PROTOCOL_MANAGER) {
        minStakeBatchAmount = _minStakeBatchAmount;

        emit ProtocolConfigChanged(
            "setMinStakeBatchAmount",
            "setMinStakeBatchAmount",
            abi.encode(_minStakeBatchAmount)
        );
    }

    function setMinStakeAmountAVAX(uint256 _minStakeAmountAVAX) external onlyRole(ROLE_PROTOCOL_MANAGER) {
        minStakeAmountAVAX = _minStakeAmountAVAX;

        emit ProtocolConfigChanged("setMinStakeAmountAVAX", "setMinStakeAmountAVAX", abi.encode(_minStakeAmountAVAX));
    }

    function setMinUnstakeAmountStAVAX(uint256 _minUnstakeAmountStAVAX) external onlyRole(ROLE_PROTOCOL_MANAGER) {
        minUnstakeAmountStAVAX = _minUnstakeAmountStAVAX;

        emit ProtocolConfigChanged(
            "setMinUnstakeAmountStAVAX",
            "setMinUnstakeAmountStAVAX",
            abi.encode(_minUnstakeAmountStAVAX)
        );
    }

    // Setter check reflects Avalanche P-chain minimum and maximum staking periods.
    function setStakePeriod(uint256 _stakePeriod) external onlyRole(ROLE_PROTOCOL_MANAGER) {
        if (_stakePeriod < 14 days || _stakePeriod > 365 days) revert InvalidConfiguration();

        stakePeriod = _stakePeriod;

        emit ProtocolConfigChanged("setStakePeriod", "setStakePeriod", abi.encode(_stakePeriod));
    }

    // Maximum number of unstake requests a user can have open at once, to help prevent spamming.
    function setMaxUnstakeRequests(uint8 _maxUnstakeRequests) external onlyRole(ROLE_PROTOCOL_MANAGER) {
        if (_maxUnstakeRequests == 0 || _maxUnstakeRequests > 1000) revert InvalidConfiguration();

        maxUnstakeRequests = _maxUnstakeRequests;

        emit ProtocolConfigChanged("setMaxUnstakeRequests", "setMaxUnstakeRequests", abi.encode(_maxUnstakeRequests));
    }

    function setMaxProtocolControlledAVAX(uint256 _maxProtocolControlledAVAX) external onlyRole(ROLE_PROTOCOL_MANAGER) {
        maxProtocolControlledAVAX = _maxProtocolControlledAVAX;

        emit ProtocolConfigChanged(
            "setMaxProtocolControlledAVAX",
            "setMaxProtocolControlledAVAX",
            abi.encode(_maxProtocolControlledAVAX)
        );
    }

    function setPChainExportBuffer(uint256 _pChainExportBuffer) external onlyRole(ROLE_PROTOCOL_MANAGER) {
        pChainExportBuffer = _pChainExportBuffer;

        emit ProtocolConfigChanged("setPChainExportBuffer", "setPChainExportBuffer", abi.encode(_pChainExportBuffer));
    }

    function setMinClaimWaitTimeSeconds(uint64 _minimumClaimWaitTimeSeconds) external onlyRole(ROLE_PROTOCOL_MANAGER) {
        if (_minimumClaimWaitTimeSeconds > stakePeriod) revert InvalidConfiguration();
        minimumClaimWaitTimeSeconds = _minimumClaimWaitTimeSeconds;

        emit ProtocolConfigChanged(
            "setMinClaimWaitTimeSeconds",
            "setMinClaimWaitTimeSeconds",
            abi.encode(_minimumClaimWaitTimeSeconds)
        );
    }

    // Be extremely careful when modifying this value: it must be large enough that the unstake queue
    // doesn't grow faster than it can be processed, but small enough that in processing it doesn't
    // reach the Avalanche block gas limit (currently 8M, much smaller than Ethereum's 30M limit).
    // Approximate ranges can be found experimentally using `forge test --gas-report`.
    function setUnstakeLoopBound(uint64 _unstakeLoopBound) external onlyRole(ROLE_PROTOCOL_MANAGER) {
        if (_unstakeLoopBound == 0 || _unstakeLoopBound > 1000) revert InvalidConfiguration();

        unstakeLoopBound = _unstakeLoopBound;

        emit ProtocolConfigChanged("setUnstakeLoopBound", "setUnstakeLoopBound", abi.encode(_unstakeLoopBound));
    }

    // -------------------------------------------------------------------------
    // Overrides
    // -------------------------------------------------------------------------

    // Necessary overrides to handle conflict between `Context` and `ContextUpgradeable`.

    function _msgSender() internal view override(Context, ContextUpgradeable) returns (address) {
        return Context._msgSender();
    }

    function _msgData() internal view override(Context, ContextUpgradeable) returns (bytes calldata) {
        return Context._msgData();
    }
}
