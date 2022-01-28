// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.7;

import { IERC20Like, IPoolFactoryLike, IPoolLike, IStakeLockerLike } from "../../interfaces/Interfaces.sol";

import { IDebtLocker } from "../../../modules/debt-locker/contracts/interfaces/IDebtLocker.sol";

contract PoolDelegate {

    function approve(address token, address account, uint256 amt) external {
        IERC20Like(token).approve(account, amt);
    }

    function claim(address pool, address loan, address dlFactory) external returns (uint256[7] memory) {
        return IPoolLike(pool).claim(loan, dlFactory);
    }

    function createPool(
        address poolFactory,
        address liquidityAsset,
        address stakeAsset,
        address slFactory,
        address llFactory,
        uint256 stakingFee,
        uint256 delegateFee,
        uint256 liquidityCap
    )
        external returns (address liquidityPool)
    {
        liquidityPool = IPoolFactoryLike(poolFactory).createPool(
            liquidityAsset,
            stakeAsset,
            slFactory,
            llFactory,
            stakingFee,
            delegateFee,
            liquidityCap
        );
    }

    function debtLocker_setAllowedSlippage(address debtLocker_, uint256 slippage_) external {
        IDebtLocker(debtLocker_).setAllowedSlippage(slippage_);
    }

    function debtLocker_setMinRatio(address debtLocker_, uint256 slippage_) external {
        IDebtLocker(debtLocker_).setMinRatio(slippage_);
    }

    function finalize(address pool) external {
        IPoolLike(pool).finalize();
    }

    function fundLoan(address pool, address loan, address dlFactory, uint256 amt) external {
        IPoolLike(pool).fundLoan(loan, dlFactory, amt);
    }

    function setAllowList(address pool, address account, bool status) external {
        IPoolLike(pool).setAllowList(account, status);
    }

    function setOpenToPublic(address pool, bool status) external {
        IPoolLike(pool).setOpenToPublic(status);
    }

    function stake(address stakeLocker, uint256 amt) external {
        IStakeLockerLike(stakeLocker).stake(amt);
    }

    function triggerDefault(address pool, address loan, address dlFactory) external {
        IPoolLike(pool).triggerDefault(loan, dlFactory);
    }
    
}
