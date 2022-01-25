// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.7;

import { TestUtils, StateManipulations } from "../../modules/contract-test-utils/contracts/test.sol";

import { IMapleLoan } from "../../modules/loan/contracts/interfaces/IMapleLoan.sol";

import { Borrower }     from "./accounts/Borrower.sol";
import { PoolDelegate } from "./accounts/PoolDelegate.sol";

import { WETHOracleMock } from "./mocks/Mocks.sol";

import { BPoolLike, BPoolFactoryLike, ERC20Like, Hevm, LoanInitializerLike, LoanLike, MapleGlobalsLike, PoolLike } from "../interfaces/Interfaces.sol";

import { AddressRegistry } from "../AddressRegistry.sol";

contract WethSimulation is AddressRegistry, StateManipulations, TestUtils {

    uint256 constant WAD = 10 ** 18;
    uint256 constant RAY = 10 ** 27;
    uint256 constant RAD = 10 ** 45;
    uint256 constant BTC = 10 ** 8;
    uint256 constant USD = 10 ** 6;

    address[3] calcs;

    ERC20Like constant weth = ERC20Like(WETH);
    ERC20Like constant mpl = ERC20Like(MPL);

    PoolDelegate      poolDelegate;
    PoolLike          pool;
    WETHOracleMock    oracleMock;

    uint256 start;

    function setUp() public {

        start = block.timestamp;

        calcs = [REPAYMENT_CALC, LATEFEE_CALC, PREMIUM_CALC];

        oracleMock = new WETHOracleMock();

        _setUpMapleWethPool();
    }

    function test_simpleLoan() external {

        Borrower borrower = new Borrower();

        emit log("after borrower");

        LoanLike loan = LoanLike(_createLoan(borrower, 0, 1_000_000 * WAD));

        /*************************************/
        /*** Drawdown and make 1st payment ***/
        /*************************************/

        _fundLoanAndDrawdown(borrower, address(loan), 1_000_000 * WAD);

        hevm.warp(start + 30 days);

        _makePayment(address(loan), address(borrower));

        /********************************/
        /*** Claim Interest into Pool ***/
        /********************************/

        uint256 poolBalanceBefore = weth.balanceOf(address(pool));

        poolDelegate.claim(address(pool), address(loan), DL_FACTORY);

        uint256 poolBalanceAfter = weth.balanceOf(address(pool));

        emit log_named_uint("ball diff", poolBalanceAfter - poolBalanceBefore);

        // // assertTrue(poolBalanceAfter - poolBalanceBefore > 0);
        // /*************************/
        // /*** Make last payment ***/
        // /*************************/

        // hevm.warp(start + 60 days);

        // _makePayment(address(loan), address(borrower));

        // /********************************/
        // /*** Claim Interest into Pool ***/
        // /********************************/

        // poolBalanceBefore = weth.balanceOf(address(pool));

        // poolDelegate.claim(address(pool), address(loan), DL_FACTORY);

        // poolBalanceAfter = weth.balanceOf(address(pool));

        // emit log_named_uint("ball diff", poolBalanceAfter - poolBalanceBefore);

        // assertTrue(poolBalanceAfter - poolBalanceBefore > 0);
    }

    // function test_defaulted_loan() external {
    //     Borrower borrower = new Borrower();

    //     LoanLike loan = LoanLike(_createLoan(borrower, [1000, 60, 30, uint256(1_000_000 * WAD), 2000]));

    //     /*************************************/
    //     /*** Drawdown and make 1st payment ***/
    //     /*************************************/

    //     _fundLoanAndDrawdown(borrower, address(loan), 1_000_000 * WAD);

    //     hevm.warp(start + 60 days);

    //     /***********************/
    //     /*** Trigger default ***/
    //     /***********************/

    //     poolDelegate.triggerDefault(address(pool), address(loan), DL_FACTORY);

    // }

    /************************/
    /*** Helper Functions ***/
    /************************/

    function _setUpMapleWethPool() internal {

        /*********************/
        /*** Set up actors ***/
        /*********************/

        // Grant address(this) auth access to globals
        hevm.store(MAPLE_GLOBALS, bytes32(uint256(1)), bytes32(uint256(uint160(address(this)))));

        poolDelegate = new PoolDelegate();

        /************************************/
        /*** Set up MPL/WETH Balancer Pool ***/
        /************************************/

        uint256 wethAmount = 0.001 ether;
        uint256 mplAmount  = 1 ether;  // $100k of MPL

        erc20_mint(WETH, 3, address(this), wethAmount);
        erc20_mint(MPL, 0, address(this), mplAmount);

        // Initialize MPL/WETH Balancer Pool
        BPoolLike bPool = BPoolLike(BPoolFactoryLike(BPOOL_FACTORY).newBPool());
        weth.approve(address(bPool), type(uint256).max);
        mpl.approve(address(bPool), type(uint256).max);
        bPool.bind(WETH, wethAmount, 5 ether);
        bPool.bind(MPL, mplAmount, 5 ether);
        bPool.finalize();

        // Transfer all BPT to Pool Delegate for initial staking
        bPool.transfer(address(poolDelegate), 40 * WAD);  // Pool Delegate gets enought BPT to stake

        /*************************/
        /*** Configure Globals ***/
        /*************************/

        MapleGlobalsLike globals = MapleGlobalsLike(MAPLE_GLOBALS);

        globals.setLiquidityAsset(WETH, true);
        globals.setPoolDelegateAllowlist(address(poolDelegate), true);
        globals.setValidBalancerPool(address(bPool), true);
        globals.setPriceOracle(WETH, address(oracleMock));

        /*******************************************************/
        /*** Set up new WETH liquidity pool, closed to public ***/
        /*******************************************************/

        // Create a WETH pool with a 5m liquidity cap
        pool = PoolLike(poolDelegate.createPool(POOL_FACTORY, WETH, address(bPool), SL_FACTORY, LL_FACTORY, 1000, 1000, 5_000_000 ether));

        // Stake BPT for insurance and finalize pool
        poolDelegate.approve(address(bPool), pool.stakeLocker(), type(uint256).max);
        poolDelegate.stake(pool.stakeLocker(), bPool.balanceOf(address(poolDelegate)));
        poolDelegate.finalize(address(pool));
        poolDelegate.setOpenToPublic(address(pool), true);

        //mint to pool
        erc20_mint(WETH, 3, address(this), 2_000_000 ether);
        weth.approve(address(pool), 2_000_000 ether);

        pool.deposit(2_000_000 ether);
    }

     function _createLoan(Borrower borrower, uint256 collaretalRequired, uint256 principalRequested) internal returns (address loan) {
        address[2] memory assets = [WBTC, WETH];

        uint256[3] memory termDetails = [
            uint256(10 days),  // 10 day grace period
            uint256(30 days),  // 30 day payment interval
            uint256(3)
        ];

        // 250 BTC @ $58k = $14.5m = 14.5% collateralized, interest only
        uint256[3] memory requests = [collaretalRequired, principalRequested, principalRequested];

        uint256[4] memory rates = [uint256(0.12e18), uint256(0), uint256(0), uint256(0.6e18)];


        bytes memory arguments = LoanInitializerLike(LOAN_INITIALIZER).encodeArguments(address(borrower), assets, termDetails, requests, rates);

        bytes32 salt = keccak256(abi.encodePacked("salt"));

        loan = borrower.mapleProxyFactory_createInstance(address(LOAN_FACTORY), arguments, salt);
    }

    function _fundLoanAndDrawdown(Borrower borrower, address loan, uint256 fundAmount) internal {
        poolDelegate.fundLoan(address(pool), loan, DL_FACTORY, fundAmount);

        uint256 drawableFunds      = IMapleLoan(loan).drawableFunds();
        uint256 collateralRequired = LoanLike(loan).getAdditionalCollateralRequiredFor(drawableFunds);

        if (collateralRequired > 0) {
            erc20_mint(WBTC, 0, address(borrower), collateralRequired);
            borrower.approve(WBTC, loan, collateralRequired);
        }

        borrower.loan_drawdownFunds(loan, drawableFunds, address(borrower));
    }

    function _makePayment(address loan, address borrower) internal returns (uint256 principalPortion, uint256 interestPortion) {
        ( principalPortion, interestPortion ) = LoanLike(loan).getNextPaymentBreakdown();

        uint256 total = principalPortion + interestPortion;

        erc20_mint(WETH, 3, address(borrower), total);
        Borrower(borrower).approve(WETH, loan, total);
        Borrower(borrower).loan_makePayment(loan, total);
    }
}

