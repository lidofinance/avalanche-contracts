import random
import time
from web3 import Web3

# Fuji RPC
custom_rpc_url = "https://api.avax-test.network/ext/bc/C/rpc"

# Deployed contract address
contract_address = "0xc36182FF81E50Ca1Fa5EBEb1085ff5802C17CF3D"

# Caller account and private key
caller_address = "0x27F957c465214d9C3AF0bf10e52e68bd839c66d4"
private_key = "c1f5dee103505d9aaf6e2f25bf8c9bcdc984d27c221787ee95a215790567c864"

# ABI of the contract (just the methods under test)
contract_abi = [
    {
        "inputs": [{"internalType": "address", "name": "referral", "type": "address"}],
        "name": "deposit",
        "outputs": [],
        "stateMutability": "payable",
        "type": "function"
    },
    {
        "inputs": [{"internalType": "uint256", "name": "stAVAXAmount", "type": "uint256"}],
        "name": "requestWithdrawal",
        "outputs": [
            {"internalType": "uint256", "name": "", "type": "uint256"}
        ],
        "stateMutability": "nonpayable",
        "type": "function"
    },
    {
        "inputs": [],
        "name": "initiateStake",
        "outputs": [{"internalType": "uint256", "name": "", "type": "uint256"}],
        "stateMutability": "nonpayable",
        "type": "function"
    }
]

# Web3 and contract setup
w3 = Web3(Web3.HTTPProvider(custom_rpc_url))
contract = w3.eth.contract(address=contract_address, abi=contract_abi)


def random_stake_amount():
    # Generate random stake amount between 0.1 and 0.2
    return random.uniform(0.1, 0.2)


def call_deposit_method(referral_address, deposit_amount, nonce):
    # Call the deposit contract method with the given referrer and amount of AVAX
    txn = contract.functions.deposit(referral_address).build_transaction({
        'chainId': w3.eth.chain_id,
        'gas': 900000,
        'gasPrice': w3.eth.gas_price,
        'nonce': nonce,
        'value': w3.to_wei(deposit_amount, 'ether'),
        'from': caller_address,
    })

    signed_txn = w3.eth.account.sign_transaction(txn, private_key)
    txn_hash = w3.eth.send_raw_transaction(signed_txn.rawTransaction)
    return txn_hash


def call_initiate_stake_method(nonce):
    # Call the initiateStake contract method
    txn = contract.functions.initiateStake().build_transaction({
        'chainId': w3.eth.chain_id,
        'gas': 900000,
        'gasPrice': w3.eth.gas_price,
        'nonce': nonce,
        'from': caller_address,
    })

    signed_txn = w3.eth.account.sign_transaction(txn, private_key)
    txn_hash = w3.eth.send_raw_transaction(signed_txn.rawTransaction)
    return txn_hash


def call_request_withdrawal_method(stavax_amount, nonce):
    # Call the requestWithdrawal contract method with the given referrer and amount of AVAX
    stavax_wei = w3.to_wei(stavax_amount, 'ether')
    txn = contract.functions.requestWithdrawal(stavax_wei).build_transaction({
        'chainId': w3.eth.chain_id,
        'gas': 900000,
        'gasPrice': w3.eth.gas_price,
        'nonce': nonce,
        'from': caller_address,
    })

    signed_txn = w3.eth.account.sign_transaction(txn, private_key)
    txn_hash = w3.eth.send_raw_transaction(signed_txn.rawTransaction)
    return txn_hash


# Fetch nonce to order transactions correctly
nonce = w3.eth.get_transaction_count(caller_address)


def stress_test_deposit():
    # Loop calling deposit method each second and initiateStake method every 30 seconds.
    # Loop exits after 1,000 contract calls have been made.
    iteration = 1
    while True:
        stake_amount = random_stake_amount()
        txn_hash = call_deposit_method(caller_address, stake_amount, nonce)
        print(
            f"Deposit transaction: {txn_hash.hex()}, stake: {stake_amount} AVAX")

        if iteration % 30 == 0:
            nonce += 1
            txn_hash = call_initiate_stake_method(nonce)
            print(f"Initiate stake transaction: {txn_hash.hex()}")

        if iteration >= 1000:
            exit()

        iteration += 1
        nonce += 1

        time.sleep(1)  # Every second


def stress_test_withdrawal():
    # Loop calling requestWithdrawal method each second.
    # Loop exits after 100 contract calls have been made.
    iteration = 1
    while True:
        unstake_amount = random_stake_amount()
        txn_hash = call_request_withdrawal_method(unstake_amount, nonce)
        print(
            f"Withdraw transaction: {txn_hash.hex()}, amount: {unstake_amount} AVAX")

        if iteration >= 100:
            exit()

        iteration += 1
        nonce += 1

        time.sleep(1)  # Every second
