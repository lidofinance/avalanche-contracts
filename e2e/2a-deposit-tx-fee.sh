#!/bin/sh

MPC_MANAGER_ADDRESS=$1

if [ -z $MPC_MANAGER_ADDRESS ]
then
    echo "Please supply MpcManager address."
    exit 1
fi


ETHER=000000000000000000
VALUE=10${ETHER}

ROLE_DEFAULT_ADMIN="0x8db97C7cEcE249c2b98bDC0226Cc4C2A57BF52FC"
ROLE_DEFAULT_ADMIN_PK="56289e99c94b6912bfc12adc093c9b51124f0dc54ac7a766b2bc5ccf558d8027"
C_CHAIN_RPC_URL="http://127.0.0.1:9650/ext/bc/C/rpc"
MPC_PLAYER_PUBKEYS=["0xc20e0c088bb20027a77b1d23ad75058df5349c7a2bfafff7516c44c6f69aa66defafb10f0932dc5c649debab82e6c816e164c7b7ad8abbe974d15a94cd1c2937","0xd0639e479fa1ca8ee13fd966c216e662408ff00349068bdc9c6966c4ea10fe3e5f4d4ffc52db1898fe83742a8732e53322c178acb7113072c8dc6f82bbc00b99","0x73ee5cd601a19cd9bb95fe7be8b1566b73c51d3e7e375359c129b1d77bb4b3e6f06766bde6ff723360cee7f89abab428717f811f460ebf67f5186f75a9f4288d"]
MPC_GROUP_ID="3726383e52fd4cb603498459e8a4a15d148566a51b3f5bfbbf3cac7b61647d04"


LAST_GEN_ADDRESS=$(cast call --rpc-url $C_CHAIN_RPC_URL $MPC_MANAGER_ADDRESS "lastGenAddress()")
LAST_GEN_ADDRESS=0x${LAST_GEN_ADDRESS: -40}

cast send --gas-limit 900000 --rpc-url $C_CHAIN_RPC_URL --from $ROLE_DEFAULT_ADMIN --private-key $ROLE_DEFAULT_ADMIN_PK --value $VALUE -- $LAST_GEN_ADDRESS
