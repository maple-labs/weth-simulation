// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.7;

import { IERC20Like, IPoolLike } from "../../interfaces/Interfaces.sol";

contract LP {

    function approve(address token, address account, uint256 amount) external {
        IERC20Like(token).approve(account, amount);
    }

    function deposit(address pool, uint256 amount) external {
        IPoolLike(pool).deposit(amount);
    }

    function withdraw(address pool, uint256 amount) external {
        IPoolLike(pool).withdraw(amount);
    }

    function intendToWithdraw(address pool) external {
        IPoolLike(pool).intendToWithdraw();
    }

}
