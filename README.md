# Lido on Avalanche Contracts

### Setup

One time:

1. Install [`forge`](https://github.com/gakonst/foundry#installation).
1. Run `foundryup`
1. Run `forge install` in this repo to install dependencies.
1. Run `forge test` to check everything is working.

To see any `forge` assertion failure details or console logs, run `forge test` with `-vv`

#### Avalanche Local Network

1. Make sure you have `go` installed (`brew install go`).
1. Install the `Taskfile` binary with `brew install go-task/tap/go-task` (or [see alternatives](https://taskfile.dev/#/installation))
1. Download an `avalanchego` binary (or build from source) https://github.com/ava-labs/avalanchego/releases.
1. Extract the binary, and place the `build` folder in the `network` directory.
1. `cd` into the `network` directory and run `go mod download`.
1. From within the `network` directory run `go run main.go` or from the `contracts` directory run `go run network/main.go` to run a local Avalanche network.

The local network has a few pre-funded accounts to make development easier:

- `Contract Deployer` - `0x8db97C7cEcE249c2b98bDC0226Cc4C2A57BF52FC` PK `56289e99c94b6912bfc12adc093c9b51124f0dc54ac7a766b2bc5ccf558d8027`
- 🐳 `Wendy` - `0xf195179eEaE3c8CAB499b5181721e5C57e4769b2` PK `a7f3a9981d794d4849f296b0406bd4ee9aa5bfa03208954d93e5d61f965bb201`
- 🦐 `Sammy` - `0x3e46faFf7369B90AA23fdcA9bC3dAd274c41E8E2` PK `0d4c5da04cb1a1292ac933f49722a49f20e4284ab268d4cd31119ac90e91117e`
- 🔮⭐️ `Oracle Admin` - `0x8e7D0f159e992cfC0ee28D55C600106482a818Ea` PK `a87518b3691061b9de6dd281d2dda06a4fe3a2c1b4621ac1e05d9026f73065bd`
- 🔮 `Oracle 1` - `0x03C1196617387899390d3a98fdBdfD407121BB67` PK `a54a5d692d239287e8358f27caee92ab5756c0276a6db0a062709cd86451a855`
- 🔮 `Oracle 2` - `0x6C58f6E7DB68D9F75F2E417aCbB67e7Dd4e413bf` PK `86a5e025e16a96e2706d72fd6115f2ee9ae1c5dfc4c53894b70b19e6fc73b838`
- 🔮 `Oracle 3` - `0xa7bB9405eAF98f36e2683Ba7F36828e260BD0018` PK `d876abc4ef78972fc733651bfc79676d9a6722626f9980e2db249c22ed57dbb2`
- 🐪 `MPC Player 1` - `0x3051bA2d313840932B7091D2e8684672496E9A4B` PK `59d1c6956f08477262c9e827239457584299cf583027a27c1d472087e8c35f21`
- 🐪 `MPC Player 2` - `0x7Ac8e2083E3503bE631a0557b3f2A8543EaAdd90` PK `6c326909bee727d5fc434e2c75a3e0126df2ec4f49ad02cdd6209cf19f91da33`
- 🐪 `MPC Player 3` - `0x3600323b486F115CE127758ed84F26977628EeaA` PK `5431ed99fbcc291f2ed8906d7d46fdf45afbb1b95da65fecd4707d16a6b3301b`
- 🏁 `Initiator` - `0xbfE4168b9d65BFddB21c9E3d18bC82B774bB99d8` PK `676be76d4db5ee0a5b3ee5632646ee6c9f527c793885c8a8420f78e682943ceb`

The network stores state in the `node-N` directories in the `network` folder. This means you can kill and restart the network without losing state. You should be able to use MetaMask like normal to test out the network.

To set up MetaMask for the local network, add:

RPC URL: `http://127.0.0.1:9650/ext/bc/C/rpc`
Chain ID: `43112`

#### Test Admin Accounts

The default deploy script uses the following accounts for testing:

- `Pause admin` - `0x000f54f73696298dEDffB4c37f8B6564F486EAA3` PK `13f21141047f0771acec5295eeed52f335744cfe11ef322f5143ecbdbb4048da`
- `Proxy admin` - `0x999a1D7349249B2a93B512f4ffcBF03DB760d15B` PK `f650126bfe6e9b5191b5fd33e1f500d38dad2c6022ad02da46c454e488e16b85`
- `Lido fee address` - `0x11144C7f850415Ac4Fb446A6fE76b1DbD533FC55` PK `9230e8f42dc71541d791e98aab7824381df0464568368e760c5312cf4d4422c2`
- `Author fee address` - `0x222D9E71E9f66e0B7cB2Ba837Be1B9B87052e612` PK `f43abd9a5c4a94d97923816aa2401ee5231ff2c99d08c63a27ed53c5b6a449cb`

These are for use in test only, they should never be used in mainnet.

#### Setting NodeIDs

We need to run an occasional process to change the list of validator NodeIDs which the oracle knows about. Unfortunately, due to block gas limits, we have to do this in multiple transactions across many blocks. There is a script called `OracleAddNodes` which has 3 functions which need to be called:

1. `startUpdate(oracleAddress)` - Start the update. This will pull all nodes from the network and write them to a file, as well as triggering the start of the update on the contract.
2. `addNodes(oracleAddress, startIndex)` - Add some nodes from the list, starting at index `startIndex`. You should run this script multiple times until no more nodes are added, starting at `startIndex` 0 and stopping when the script tells you there's nothing left to do.
3. `endUpdate(oracleAddress)` - Call this at the end to finalize the node update process.

### Deployment

You can deploy to the local network using the `Deploy.t.sol` contract with `forge script`. The syntax is identical to the `cast` command:

```
forge script src/deploy/Deploy.t.sol --sig "deploy()" --broadcast --rpc-url <RPC_URL> --private-key <PRIVATE_KEY>
```

This uses the pre-funded AVAX "Contract Deployer" address above for deployment. Other addresses and roles can be defined during deploy or afterwards via OpenZeppelin `AccessControl.sol` methods.

`RPC_URL` options include `http://127.0.0.1:9650/ext/bc/C/rpc` for local development and `https://api.avax-test.network/ext/bc/C/rpc` for Fuji testnet.

### Interaction

Use `cast` to call contract functions directly. Examples:

- Calling a method: `cast call <ADDRESS> "deposit()" --rpc-url <RPC_URL>`
- Sending AVAX to a `payable` method: `cast send --rpc-url <RPC_URL> --from <ADDRESS> --private-key <PRIVATE_KEY> --value 1 <ADDRESS> "deposit()"`

You can also use the `task` command, which has the RPC URL pre-set: `task call -- <ADDRESS> "deposit()"`

To pass arguments to a function, you'll need to split them out: `task call -- <ADDRESS> "deposit(uint256)" 1`

### Testing

Unit tests are run with `forge test`. Integration tests are run using [Jest](https://jestjs.io/docs/getting-started_) with `jest integration`.

Important: integration tests expect that the `AVALIDO` and `VALIDATOR_ORACLE` environment variables have been set to the deployed contract addresses.
