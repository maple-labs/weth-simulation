// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.7;

contract WETHOracleMock {
    function getLatestPrice() public view returns (int256) {
        return 3000 ether;
    }
}