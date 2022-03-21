# WETH Pool Simulation

![Foundry CI](https://github.com/maple-labs/loan/actions/workflows/push-to-main.yml/badge.svg) [![License: AGPL v3](https://img.shields.io/badge/License-AGPL%20v3-blue.svg)](https://www.gnu.org/licenses/agpl-3.0)

This repository is used to test new smart contract code against external mainnet contracts, including previously deployed Maple protocol contracts that are currently in production. This codebase is actively being developed and improved, to ensure maximum test coverage and security of contracts before deployment.

## Testing and Development
#### Setup
```sh
git clone git@github.com:maple-labs/contract-test-suite.git
cd contract-test-suite
make init
```
#### Running Tests
- To run all tests: `make test` (runs `./test.sh`)
- To run a specific test function: `./test.sh -t <test_name>` (e.g., `./test.sh -t test_endToEndLoan`)
- To run tests with a specified number of fuzz runs: `./test.sh -r <runs>` (e.g., `./test.sh -t test_endToEndLoan -r 10000`)

This project was built using [Foundry](https://github.com/gakonst/Foundry).

## About Maple
[Maple Finance](https://maple.finance) is a decentralized corporate credit market. Maple provides capital to institutional borrowers through globally accessible fixed-income yield opportunities.

For all technical documentation related to the currently deployed Maple protocol, please refer to the maple-core GitHub [wiki](https://github.com/maple-labs/maple-core/wiki).

For all technical documentation related to contracts currently in development, please refer to the LoanV2 GitHub [wiki](https://github.com/maple-labs/loan/wiki).

---

<p align="center">
  <img src="https://user-images.githubusercontent.com/44272939/116272804-33e78d00-a74f-11eb-97ab-77b7e13dc663.png" height="100" />
</p>
