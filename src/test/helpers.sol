// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import "openzeppelin-contracts/contracts/utils/Strings.sol";
import "openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {Test} from "forge-std/Test.sol";

import "../ValidatorSelector.sol";
import "../MpcManager.sol";
import "../Treasury.sol";

address constant ZERO_ADDRESS = 0x0000000000000000000000000000000000000000;
address constant REFERRAL_ADDRESS = 0xDeaDbeefdEAdbeefdEadbEEFdeadbeEFdEaDbeeF;
// Note: if AccessControl suddenly fails, and there has been a Forge update, the address below may have changed
address constant DEPLOYER_ADDRESS = 0x34A1D3fff3958843C43aD80F30b94c510645C316;
address constant PAUSE_ADMIN_ADDRESS = DEPLOYER_ADDRESS;
address constant USER1_ADDRESS = 0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045;
address constant USER2_ADDRESS = 0x220866B1A2219f40e72f5c628B65D54268cA3A9D;
address constant ORACLE_ADMIN_ADDRESS = 0xf195179eEaE3c8CAB499b5181721e5C57e4769b2; // Wendy the whale gets to manage the oracle 🐳
address constant ROLE_PROXY_ADMIN = 0x3e46faFf7369B90AA23fdcA9bC3dAd274c41E8E2; // Sammy the shrimp gets to manage the proxy 🦐
string constant VALIDATOR_1 = "NodeID-P7oB2McjBGgW2NXXWVYjV8JEDFoW9xDE5";
string constant VALIDATOR_2 = "NodeID-GWPcbFJZFfZreETSoWjPimr846mXEKCtu";
string constant VALIDATOR_3 = "NodeID-NFBbbJ4qCmNaCzeW7sxErhvWqvEQMnYcN";
address constant WHITELISTED_ORACLE_1 = 0x03C1196617387899390d3a98fdBdfD407121BB67;
address constant WHITELISTED_ORACLE_2 = 0x6C58f6E7DB68D9F75F2E417aCbB67e7Dd4e413bf;
address constant WHITELISTED_ORACLE_3 = 0xa7bB9405eAF98f36e2683Ba7F36828e260BD0018;
address constant WHITELISTED_ORACLE_4 = 0xE339767906891bEE026285803DA8d8F2f346842C;
address constant WHITELISTED_ORACLE_5 = 0x0309a747a34befD1625b5dcae0B00625FAa30460;
address constant MPC_ADMIN_ADDRESS = ORACLE_ADMIN_ADDRESS;
address constant MPC_PLAYER_1_ADDRESS = 0x3600323b486F115CE127758ed84F26977628EeaA;
address constant MPC_PLAYER_2_ADDRESS = 0x3051bA2d313840932B7091D2e8684672496E9A4B;
address constant MPC_PLAYER_3_ADDRESS = 0x7Ac8e2083E3503bE631a0557b3f2A8543EaAdd90;
bytes constant MPC_PLAYER_1_PUBKEY = hex"73ee5cd601a19cd9bb95fe7be8b1566b73c51d3e7e375359c129b1d77bb4b3e6f06766bde6ff723360cee7f89abab428717f811f460ebf67f5186f75a9f4288d";
bytes constant MPC_PLAYER_2_PUBKEY = hex"c20e0c088bb20027a77b1d23ad75058df5349c7a2bfafff7516c44c6f69aa66defafb10f0932dc5c649debab82e6c816e164c7b7ad8abbe974d15a94cd1c2937";
bytes constant MPC_PLAYER_3_PUBKEY = hex"d0639e479fa1ca8ee13fd966c216e662408ff00349068bdc9c6966c4ea10fe3e5f4d4ffc52db1898fe83742a8732e53322c178acb7113072c8dc6f82bbc00b99";
bytes constant MPC_GENERATED_PUBKEY = hex"c6184cd4d6e7eeadd09410fe06a30bc06355c8c8c4dabd5c1e2d3c30d6ba42386bac735d7f4e7d264ac8741ab382a7868bf1bfa3f3b74a67f83d032309d4599c";

uint256 constant INDEX_1 = 0x800000000000000000;
uint256 constant INDEX_2 = 0x400000000000000000;
uint256 constant INDEX_3 = 0x200000000000000000;
bytes32 constant MPC_GROUP_HASH = hex"a472900a75fa9af71b37d10313bfc1d9e09b948adddd36d020e1a2be01396aad";
bytes32 constant MPC_GROUP_ID = hex"a472900a75fa9af71b37d10313bfc1d9e09b948adddd36d020e1a2be01030100";
bytes32 constant MPC_PARTICIPANT1_ID = hex"a472900a75fa9af71b37d10313bfc1d9e09b948adddd36d020e1a2be01030101";
bytes32 constant MPC_PARTICIPANT2_ID = hex"a472900a75fa9af71b37d10313bfc1d9e09b948adddd36d020e1a2be01030102";
bytes32 constant MPC_PARTICIPANT3_ID = hex"a472900a75fa9af71b37d10313bfc1d9e09b948adddd36d020e1a2be01030103";
address constant MPC_GENERATED_ADDRESS = 0x24CE57563754DBEc6a92b8bA10af2D2416C237e4;

address constant MPC_BIG_P01_ADDRESS = 0x6063e982fc103F3f9453D5cC2b1568dd0Bd0B7C0;
address constant MPC_BIG_P02_ADDRESS = 0x97196D165E4131584A1d4B0C86d3188fE79412EA;
address constant MPC_BIG_P03_ADDRESS = 0xA76E808f35Ae49322d1f27591f82f1EcC4823f70;
address constant MPC_BIG_P04_ADDRESS = 0x940D2d6A6dcC3410491F9889259a02CE0DfDAB32;
address constant MPC_BIG_P05_ADDRESS = 0xD3860A040f0F255572bbFc7e47a60812634eB1D1;
address constant MPC_BIG_P06_ADDRESS = 0x063664E70f690f0368c60371749C4992e727E9E5;
address constant MPC_BIG_P07_ADDRESS = 0xFAA0571D559982Add1cDd2d017e1d2Bef6b5CA94;
address constant MPC_BIG_P08_ADDRESS = 0xe852185c0E61020c24317431434BeD1d51E9C565;
address constant MPC_BIG_P09_ADDRESS = 0xD9252E167eCaDC2f2649eCfAF2A308669414fAA2;
address constant MPC_BIG_P10_ADDRESS = 0x337Aae2E1d73a8416281db6F58cd10FE3cF0270f;
address constant MPC_BIG_P11_ADDRESS = 0x1B40cD37f1A3B67F7aeA39ECFA5f8A1F1d1C2805;
address constant MPC_BIG_P12_ADDRESS = 0x2fFB61C7833f52419667cf14E4b28ba2e85FC17e;

bytes constant MPC_BIG_P01_PUBKEY = hex"04e3edfbc73a1f0fb23a832b0520adc00a5c13c3c7079ef48547f255eda37564316e7dbd421266af161ef32f3ce1c33df2fb93dd99ce1a3bd32e3796ec2e6531";
bytes constant MPC_BIG_P02_PUBKEY = hex"1b86bff86fa0368498958789efde10d940984c949bb4ca6af9b2ef2324c07381ae28cec8aedbde40b5460b2e05a25ac7a5ee65c301b68e967761c76c061105f9";
bytes constant MPC_BIG_P03_PUBKEY = hex"293d0b9ba1d9e964214046a7955869a6c0da18076dcd95e978c1a4cee05b69aea8566a81309cf218e378d94b60aa999a6641c4821b03bc902397f46da92d2f85";
bytes constant MPC_BIG_P04_PUBKEY = hex"4e4c0c6ca3625808083faab3452fd3bfe5aefea2bc703b7c22b6d485156c8439b1a3bc4a6908f383879a00e63cfc9498aed96de7baebf2322394858e2e556aa3";
bytes constant MPC_BIG_P05_PUBKEY = hex"4f82f88cca6ac57866f21014fbc4f1c0d30ee105071c9ceb015a4e7f5c81e133252e73071d97cb1b05b54605f1d7a31435597cdad6ea1303546f044ae529e556";
bytes constant MPC_BIG_P06_PUBKEY = hex"52e8483c6d2983f154a2c3d4c0c11652158064251e7780fd897f72eee2d1bf9ff899cc4fb91998ed28c6a8bb2da0ff7cb98a2eddbf81179270b72da837f3c4ea";
bytes constant MPC_BIG_P07_PUBKEY = hex"54fdc3ae9dcd703b9b070ce75d136962d71545fdab078ffdf8a297c0415cf6b666fc002e1b17eec007a986c025f6c4930ae01028a393c018bf196fb9ffe3e9e9";
bytes constant MPC_BIG_P08_PUBKEY = hex"598240e4cdf8a20b1f8d059d4bbade60a94f280a47e33136da1931eaae62026778d2de0d68b2e83e62a295b82cedbf659340a482a4db466b769ce6a54f29930a";
bytes constant MPC_BIG_P09_PUBKEY = hex"7031063a4a10c939899aee574e4f9af38a44ce2c749b10c4aa95bb47ef7ca4e0e617fc6023da47eed301bb703066012e405fd1ea0b4926db9d04ba4bc940f85e";
bytes constant MPC_BIG_P10_PUBKEY = hex"93e9525121fe370ac326e5d5d4e350e98e2df6532c35e1472f5e2d29319dc594950a4ea77f6ea802e034a978b26c6327c9055a9a49c77838cc3715a6187d8157";
bytes constant MPC_BIG_P11_PUBKEY = hex"ab5a5d015a9ada82ad194e8d8b6b2f9faf4ac74d96143da8d0c2ad34401d8566107dfb554b8cf320763d75d5ed5a06b4f4703bddd4c61f78f90bdc5b1ffef4a3";
bytes constant MPC_BIG_P12_PUBKEY = hex"f2c20457d313ea2e71a3ef0ff7611289d8877e64f56b1860e051a24c2b7286af107ce65824118e41219fb863a3bfe8a4141b2a1d09ad84439ad4de051ed62330";

abstract contract Helpers is Test {
    function validatorSelectMock(
        address validatorSelector,
        string memory node,
        uint256 amount,
        uint256 remaining
    ) public {
        string[] memory idResult = new string[](1);
        idResult[0] = node;

        uint256[] memory amountResult = new uint256[](1);
        amountResult[0] = amount;

        vm.mockCall(
            validatorSelector,
            abi.encodeWithSelector(ValidatorSelector.selectValidatorsForStake.selector),
            abi.encode(idResult, amountResult, remaining)
        );
    }

    function stringArrayContains(string memory stringToCheck, string[] memory arrayOfStrings)
        public
        pure
        returns (bool)
    {
        for (uint256 i = 0; i < arrayOfStrings.length; i++) {
            if (keccak256(abi.encodePacked(arrayOfStrings[i])) == keccak256(abi.encodePacked(stringToCheck))) {
                return true;
            }
        }
        return false;
    }

    function addressArrayContains(address addressToCheck, address[] memory arrayOfAddresses)
        public
        pure
        returns (bool)
    {
        for (uint256 i = 0; i < arrayOfAddresses.length; i++) {
            if (keccak256(abi.encodePacked(arrayOfAddresses[i])) == keccak256(abi.encodePacked(addressToCheck))) {
                return true;
            }
        }
        return false;
    }

    function proxyWrapped(address implementation, address admin) public returns (address) {
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(implementation, admin, "");
        return address(proxy);
    }
}
