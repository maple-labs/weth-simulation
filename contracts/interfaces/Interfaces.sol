// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.7;


interface IBPoolFactoryLike {
    function newBPool() external returns (address);
}

interface IBPoolLike {
    function balanceOf(address) external view returns (uint256);
    function bind(address, uint256, uint256) external;
    function finalize() external;
    function getSpotPrice(address, address) external returns (uint256);
    function joinPool(uint poolAmountOut, uint[] calldata maxAmountsIn) external;
    function transfer(address, uint256) external returns (bool);
}

interface IERC20Like {
    function balanceOf(address) external view returns (uint256);
    function approve(address, uint256) external returns (bool);
    function transfer(address, uint256) external returns (bool);
    function totalSupply() external view returns (uint256);
}

interface Vm {
    function load(address,bytes32) external view returns (bytes32);
    function store(address,bytes32,bytes32) external;
    function warp(uint256) external;
    function expectRevert(bytes calldata) external;
}

interface ILoanFactoryLike {
    function createInstance(bytes calldata arguments_, bytes32 salt_) external returns (address instance_);
}

interface ILoanInitializerLike {
    function encodeArguments(
        address borrower_,
        address[2] memory assets_,
        uint256[3] memory termDetails_,
        uint256[3] memory amounts_,
        uint256[4] memory rates_
    ) external pure returns (bytes memory encodedArguments_);
}

interface ILoanLike {
    function getAdditionalCollateralRequiredFor(uint256 drawdown_) external view returns (uint256 additionalCollateral_);
    function drawdownFunds(uint256 amount_, address destination_) external returns (uint256 collateralPosted_);
    function getNextPaymentBreakdown() external view returns (uint256 totalPrincipalAmount_, uint256 totalInterestFees_);
    function nextPaymentDueDate() external view returns (uint256 nextPaymentDueDate_);
    function makePayment(uint256 amount_) external returns (uint256 principal_, uint256 interest_);
}

interface IMapleGlobalsLike {
    function getLatestPrice(address) external view returns (uint256);
    function setLiquidityAsset(address, bool) external;
    function setCollateralAsset(address, bool) external;
    function setPoolDelegateAllowlist(address, bool) external;
    function setPriceOracle(address, address) external;
    function setSwapOutRequired(uint256) external;
    function setValidBalancerPool(address, bool) external;
    function getLpCooldownParams() external view returns (uint256, uint256);
}

interface IPoolFactoryLike {
    function createPool(address, address, address, address, uint256, uint256, uint256) external returns (address);
}

interface IPoolLibLike {
    function getSwapOutValueLocker(address _bPool, address liquidityAsset, address stakeLocker) external view returns (uint256 swapOutValue_);
}

interface IPoolLike {
    function balanceOf(address) external view returns (uint256);
    function claim(address, address) external returns (uint256[7] memory);
    function debtLockers(address loan, address dlFactory) external returns (address);
    function deposit(uint256 amount_) external;
    function getInitialStakeRequirements() external view returns (uint256, uint256, bool, uint256, uint256);
    function getPoolSharesRequired(address, address, address, address, uint256) external view returns(uint256, uint256);
    function finalize() external;
    function fundLoan(address, address, uint256) external;
    function interestSum() external view returns (uint256 interestSum_);
    function intendToWithdraw() external;
    function liquidityLocker() external view returns (address);
    function lockupPeriod() external view returns (uint256);
    function principalOut() external view returns (uint256 principalOut_);
    function poolLosses() external view returns (uint256 poolLossess_);
    function recognizableLossesOf(address) external view returns (uint256);
    function stakeLocker() external returns (address);
    function setAllowList(address, bool) external;
    function setOpenToPublic(bool open) external;
    function superFactory() external view returns (address);
    function totalSupply() external view returns (uint256);
    function triggerDefault(address loan, address dlFactory) external;
    function withdraw(uint256) external;
    function withdrawableFundsOf(address) external view returns (uint256);
    function withdrawCooldown(address) external view returns (uint256);
}

interface IStakeLockerLike {
    function bptLosses() external view returns (uint256 bptLossess_);
    function fundsTokenBalance() external view returns (uint256 interestSums_);
    function stake(uint256) external;
    function totalSupply() external view returns (uint256);
}
