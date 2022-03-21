#!/usr/bin/env bash
set -e

while getopts t:r:p: flag
do
    case "${flag}" in
        t) test=${OPTARG};;
        r) runs=${OPTARG};;
        p) profile=${OPTARG};;
    esac
done

runs=$([ -z "$runs" ] && echo "100" || echo "$runs")

export PROPTEST_CASES=$runs
export DAPP_FORK_BLOCK=14096849

if [ -z "$test" ]; then match="[src/test/*.t.sol]"; else match=$test; fi

rm -rf out

forge test --match "$match" -vvv --lib-paths "modules" --fork-url "$ETH_RPC_URL"
