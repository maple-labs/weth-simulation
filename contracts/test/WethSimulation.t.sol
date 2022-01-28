// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.7;

import { TestUtils, StateManipulations } from "../../modules/contract-test-utils/contracts/test.sol";

import { IMapleLoan } from "../../modules/loan/contracts/interfaces/IMapleLoan.sol";    

import { IDebtLocker } from "../../modules/debt-locker/contracts/interfaces/IDebtLocker.sol";

import { Borrower }     from "./accounts/Borrower.sol";
import { Keeper }       from "./accounts/Keeper.sol";
import { PoolDelegate } from "./accounts/PoolDelegate.sol";

import { IPoolLibLike, IStakeLockerLike } from "../interfaces/Interfaces.sol";

import { SushiswapStrategy } from "../../modules/liquidations/contracts/SushiswapStrategy.sol";
import { UniswapV2Strategy } from "../../modules/liquidations/contracts/UniswapV2Strategy.sol";
import { Liquidator }        from "../../modules/liquidations/contracts/Liquidator.sol";
import { Rebalancer }        from "../../modules/liquidations/contracts/test/mocks/Mocks.sol";

import { ChainlinkOracle } from "../../modules/chainlink-oraclce/contracts/ChainlinkOracle.sol";

import { IBPoolLike, IBPoolFactoryLike, IERC20Like, IHevm, ILoanInitializerLike, IMapleGlobalsLike, IPoolLike } from "../interfaces/Interfaces.sol";

import { AddressRegistry } from "../AddressRegistry.sol";

contract WethSimulation is AddressRegistry, StateManipulations, TestUtils {

    uint256 constant WAD = 10 ** 18;
    uint256 constant RAY = 10 ** 27;
    uint256 constant RAD = 10 ** 45;
    uint256 constant BTC = 10 ** 8;
    uint256 constant USD = 10 ** 6;

    address[3] calcs;

    IERC20Like constant weth = IERC20Like(WETH);
    IERC20Like constant wbtc = IERC20Like(WBTC);
    IERC20Like constant mpl  = IERC20Like(MPL);

    IBPoolLike      bPool;
    PoolDelegate   poolDelegate;
    IPoolLike       pool;

    uint256 start;

    function setUp() public {

        start = block.timestamp;

        // calcs = [REPAYMENT_CALC, LATEFEE_CALC, PREMIUM_CALC];

        _setUpMapleWethPool();
    }

    function test_loan_endToEnd() external {

        Borrower borrower = new Borrower();

        /********************************/
        /*** Create and drawdown loan ***/
        /********************************/
        IMapleLoan loan = IMapleLoan(_createLoan(borrower, 0, 1_000_000 * WAD));

        _fundLoanAndDrawdown(borrower, address(loan), 1_000_000 * WAD);

        /********************************/
        /*** Make Payment 1 (On time) ***/
        /********************************/

        hevm.warp(loan.nextPaymentDueDate());

        // Check details for upcoming payment #1
        ( uint256 principalPortion, uint256 interestPortion ) = loan.getNextPaymentBreakdown();

        assertEq(principalPortion, 0);
        assertEq(interestPortion, 9863_013698630136000000);

        assertEq(weth.balanceOf(address(loan)), 0);

        // Make first payment
        erc20_mint(WETH, 3, address(borrower), interestPortion);
        borrower.erc20_approve(WETH, address(loan), interestPortion);
        borrower.loan_makePayment(address(loan), interestPortion);

        assertEq(weth.balanceOf(address(loan)), interestPortion);

        /************************************/
        /*** Claim Funds as Pool Delegate ***/
        // /************************************/

        uint256 pool_principalOut = pool.principalOut();
        uint256 pool_interestSum  = pool.interestSum();

        uint256 weth_liquidityLockerBal = weth.balanceOf(pool.liquidityLocker());
        uint256 weth_stakeLockerBal     = weth.balanceOf(pool.stakeLocker());

        uint256[7] memory details = poolDelegate.claim(address(pool), address(loan), address(DL_FACTORY));

        assertEq(weth.balanceOf(address(loan)), 0);

        assertEq(details[0], interestPortion);
        assertEq(details[1], interestPortion);

        uint256 ongoingFee = interestPortion * 1000 / 10_000;  // Applies to both StakeLocker and Pool Delegate since both have 10% ongoing fees

        assertEq(pool.principalOut(),                    pool_principalOut       += 0);
        assertEq(pool.interestSum(),                     pool_interestSum        += interestPortion - 2 * ongoingFee);  // 80% of interest
        assertEq(weth.balanceOf(pool.liquidityLocker()), weth_liquidityLockerBal += interestPortion - 2 * ongoingFee);  // 80% of interest
        assertEq(weth.balanceOf(pool.stakeLocker()),     weth_stakeLockerBal     += ongoingFee);                        // 10% of interest

        /********************************/
        /*** Make Payment 2 (On time) ***/
        /********************************/

        hevm.warp(loan.nextPaymentDueDate()); 

        assertEq(weth.balanceOf(address(loan)), 0);

        // Make second payment
        erc20_mint(WETH, 3, address(borrower), interestPortion);
        borrower.erc20_approve(WETH, address(loan), interestPortion);
        borrower.loan_makePayment(address(loan), interestPortion);

        assertEq(weth.balanceOf(address(loan)), interestPortion);

        /******************************/
        /*** Make Payment 3 (Final) ***/
        /******************************/

        hevm.warp(loan.nextPaymentDueDate());

        // Check details for upcoming payment #3
        ( principalPortion, interestPortion ) = loan.getNextPaymentBreakdown();

        assertEq(weth.balanceOf(address(loan)), interestPortion);

        // Make third payment
        erc20_mint(WETH, 3, address(borrower), principalPortion + interestPortion);  // Principal + interest
        borrower.erc20_approve(WETH, address(loan), principalPortion + interestPortion);
        borrower.loan_makePayment(address(loan), principalPortion + interestPortion);

        /**************************************************/
        /*** Claim Funds as Pool Delegate (Two Payments ***/
        /**************************************************/
        
        details = poolDelegate.claim(address(pool), address(loan), address(DL_FACTORY));

        assertEq(weth.balanceOf(address(loan)), 0);

        uint256 totalInterest = interestPortion * 2;

        assertEq(details[0], principalPortion + totalInterest);
        assertEq(details[1], totalInterest);
        assertEq(details[2], principalPortion);
        assertEq(details[3], 0);
        assertEq(details[4], 0);
        assertEq(details[5], 0);
        assertEq(details[6], 0);

        ongoingFee = totalInterest * 1000 / 10_000;  // Applies to both StakeLocker and Pool Delegate since both have 10% ongoing fees

        assertEq(pool.principalOut(),                    pool_principalOut       -= principalPortion);
        assertEq(pool.interestSum(),                     pool_interestSum        += totalInterest - (2 * ongoingFee));                     // 80% of interest
        assertEq(weth.balanceOf(pool.liquidityLocker()), weth_liquidityLockerBal += principalPortion + totalInterest - (2 * ongoingFee));  // 80% of interest
        assertEq(weth.balanceOf(pool.stakeLocker()),     weth_stakeLockerBal     += ongoingFee);                                           // 10% of interest
    }

    function test_triggerDefault_underCollateralized() external {

        Borrower borrower = new Borrower();

        /********************************/
        /*** Create and drawdown loan ***/
        /********************************/
        IMapleLoan loan = IMapleLoan(_createLoan(borrower, 2 * BTC, 1_000_000 * WAD));

        _fundLoanAndDrawdown(borrower, address(loan), 1_000_000 * WAD);

        /********************************/
        /*** Make Payment 1 (On time) ***/
        /********************************/

        hevm.warp(loan.nextPaymentDueDate());

        // Check details for upcoming payment #1
        ( , uint256 interestPortion ) = loan.getNextPaymentBreakdown();
        erc20_mint(WETH, 3, address(borrower), interestPortion);

        borrower.erc20_approve(WETH, address(loan), interestPortion);
        borrower.loan_makePayment(address(loan), interestPortion);

        /************************************/
        /*** Claim Funds as Pool Delegate ***/
        /************************************/

        poolDelegate.claim(address(pool),address(loan), address(DL_FACTORY));

        /********************************/
        /*** Make Payment 2 (On time) ***/
        /********************************/

        hevm.warp(loan.nextPaymentDueDate());

        // Check details for upcoming payment #2
        ( , interestPortion ) = loan.getNextPaymentBreakdown();

        // Make second payment
        erc20_mint(WETH, 3, address(borrower), interestPortion);

        borrower.erc20_approve(WETH, address(loan), interestPortion);
        borrower.loan_makePayment(address(loan), interestPortion);

        /*******************************/
        /*** Borrower Misses Payment ***/
        /*******************************/

        hevm.warp(loan.nextPaymentDueDate() + loan.gracePeriod() + 1);

        /************************************/
        /*** Claim Funds as Pool Delegate ***/
        /************************************/

        poolDelegate.claim(address(pool),address(loan), address(DL_FACTORY));

        /**************************************/
        /*** Pool Delegate triggers default ***/
        /**************************************/

        hevm.warp(loan.nextPaymentDueDate() + loan.gracePeriod() + 1);

        IDebtLocker debtLocker = IDebtLocker(pool.debtLockers(address(loan), address(DL_FACTORY))); 

        // IDebtLocker State
        assertTrue( debtLocker.liquidator() == address(0));
        assertTrue(!debtLocker.repossessed());

        // WETH/WBTC State
        assertEq(weth.balanceOf(address(loan)),       0);
        assertEq(weth.balanceOf(address(debtLocker)), 0);
        assertEq(wbtc.balanceOf(address(loan)),       2 * BTC);
        assertEq(wbtc.balanceOf(address(debtLocker)), 0);

        poolDelegate.triggerDefault(address(pool),address(loan), address(DL_FACTORY));

        // IDebtLocker State
        assertTrue(debtLocker.liquidator() != address(0));
        assertTrue(debtLocker.repossessed());

        // WETH/WBTC State
        assertEq(weth.balanceOf(address(loan)),                    0);
        assertEq(weth.balanceOf(address(debtLocker)),              0);
        assertEq(wbtc.balanceOf(address(loan)),                    0);
        assertEq(wbtc.balanceOf(address(debtLocker)),              0);
        assertEq(wbtc.balanceOf(address(debtLocker.liquidator())), 2 * BTC);

        /*******************************************************/
        /*** Pool Delegate configures liquidation parameters ***/
        /*******************************************************/

        poolDelegate.debtLocker_setAllowedSlippage(address(debtLocker), 300);  // 3% slippage allowed

        /**********************************/
        /*** Collateral gets liquidated ***/
        /**********************************/
        Keeper keeper1 = new Keeper();

        UniswapV2Strategy uniswapV2Strategy = new UniswapV2Strategy();

        _liquidate(keeper1, address(uniswapV2Strategy), debtLocker, 2 * BTC);

        /***************************************************************/
        /*** Pool delegate claims funds, triggering BPT burning flow ***/
        /***************************************************************/

        // Before state
        uint256 bpt_stakeLockerBal      = bPool.balanceOf(pool.stakeLocker());
        uint256 pool_principalOut       = pool.principalOut();
        uint256 weth_liquidityLockerBal = weth.balanceOf(pool.liquidityLocker());

        IStakeLockerLike stakeLocker = IStakeLockerLike(pool.stakeLocker());

        uint256 swapOutAmount = IPoolLibLike(ORTHOGONAL_POOL_LIB).getSwapOutValueLocker(address(bPool), WETH, address(stakeLocker));

        uint256[7] memory details = poolDelegate.claim(address(pool),address(loan), address(DL_FACTORY));

        uint256 totalPrincipal = 1_000_000 ether;
        uint256 totalRecovered = 28913375309783923686;                // Recovered from liquidation
        uint256 totalShortfall = totalPrincipal - totalRecovered;  
        uint256 totalBptBurn   = bpt_stakeLockerBal - bPool.balanceOf(address(stakeLocker));

        assertEq(details[0], totalRecovered);
        assertEq(details[1], 0);
        assertEq(details[2], 0);
        assertEq(details[3], 0);
        assertEq(details[4], 0);
        assertEq(details[5], totalRecovered);
        assertEq(details[6], totalShortfall);  

        assertEq(bPool.balanceOf(address(stakeLocker)),  bpt_stakeLockerBal - totalBptBurn);                         // Max amount of BPTs were burned
        assertEq(pool.principalOut(),                    pool_principalOut - totalPrincipal);                        // Principal out reduced by full amount
        assertEq(pool.poolLosses(),                      totalShortfall - swapOutAmount);                            // Shortfall from liquidation - BPT recovery (zero before)
        assertEq(stakeLocker.bptLosses(),                totalBptBurn);                                              // BPTs burned (zero before)
        assertEq(weth.balanceOf(pool.liquidityLocker()), weth_liquidityLockerBal + totalRecovered + swapOutAmount);  // Liquidation recovery + BPT recovery
    }

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

        uint256 wethAmount = 4 ether;
        uint256 mplAmount  = 700 ether;  
        // uint256 mplAmount = wethAmount * WAD / (usdcBPool.getSpotPrice(USDC, MPL) * WAD / 10 ** 6);

        erc20_mint(WETH, 3, address(this), wethAmount);
        erc20_mint(MPL, 0, address(this), mplAmount);

        // Initialize MPL/WETH Balancer Pool
        bPool = IBPoolLike(IBPoolFactoryLike(BPOOL_FACTORY).newBPool());
        weth.approve(address(bPool), type(uint256).max);
        mpl.approve(address(bPool), type(uint256).max);
        bPool.bind(WETH, wethAmount, 5 ether);
        bPool.bind(MPL, mplAmount, 5 ether);
        bPool.finalize();

        // Transfer max amount of burnable BPTs  
        bPool.transfer(address(poolDelegate), 99 * WAD);  // Pool Delegate gets enought BPT to stake

        /*********************/
        /*** Create Oracle ***/
        /*********************/

        address ethOracle = address(new ChainlinkOracle(ETH_USD_ORACLE,WETH, address(this)));

        /*************************/
        /*** Configure Globals ***/
        /*************************/

        IMapleGlobalsLike globals = IMapleGlobalsLike(MAPLE_GLOBALS);

        globals.setLiquidityAsset(WETH, true);
        globals.setPoolDelegateAllowlist(address(poolDelegate), true);
        globals.setValidBalancerPool(address(bPool), true);
        globals.setPriceOracle(WETH, address(ethOracle));
        globals.setSwapOutRequired(10000);

        /*******************************************************/
        /*** Set up new WETH liquidity pool, closed to public ***/
        /*******************************************************/

        // Create a WETH pool with a 5m liquidity cap
        pool = IPoolLike(poolDelegate.createPool(POOL_FACTORY, WETH, address(bPool), SL_FACTORY, LL_FACTORY, 1000, 1000, 5_000_000 ether));

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


        bytes memory arguments = ILoanInitializerLike(LOAN_INITIALIZER).encodeArguments(address(borrower), assets, termDetails, requests, rates);

        bytes32 salt = keccak256(abi.encodePacked("salt"));

        loan = borrower.mapleProxyFactory_createInstance(address(LOAN_FACTORY), arguments, salt);
    }

    function _fundLoanAndDrawdown(Borrower borrower, address loan, uint256 fundAmount) internal {
        poolDelegate.fundLoan(address(pool), loan, DL_FACTORY, fundAmount);

        uint256 drawableFunds      = IMapleLoan(loan).drawableFunds();
        uint256 collateralRequired = IMapleLoan(loan).getAdditionalCollateralRequiredFor(drawableFunds);

        if (collateralRequired > 0) {
            erc20_mint(WBTC, 0, address(borrower), collateralRequired);
            borrower.erc20_approve(WBTC, loan, collateralRequired);
        }

        borrower.loan_drawdownFunds(loan, drawableFunds, address(borrower));
    }

    function _makePayment(address loan, address borrower) internal returns (uint256 principalPortion, uint256 interestPortion) {
        ( principalPortion, interestPortion ) = IMapleLoan(loan).getNextPaymentBreakdown();

        uint256 total = principalPortion + interestPortion;

        erc20_mint(WETH, 3, address(borrower), total);
        Borrower(borrower).erc20_approve(WETH, loan, total);
        Borrower(borrower).loan_makePayment(loan, total);
    }

    function _liquidate(Keeper keeper, address strategy, IDebtLocker debtLocker, uint256 amount) internal {
        keeper.strategy_flashBorrowLiquidation(
            strategy, 
            address(debtLocker.liquidator()), 
            amount, 
            type(uint256).max,
            uint256(0),
            WBTC, 
            address(0), 
            WETH, 
            address(keeper)
        );
    } 
}

