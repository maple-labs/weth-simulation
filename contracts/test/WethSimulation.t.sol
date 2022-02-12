// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.7;

import { TestUtils, StateManipulations } from "../../modules/contract-test-utils/contracts/test.sol";

import { IMapleLoan } from "../../modules/loan/contracts/interfaces/IMapleLoan.sol";

import { IDebtLocker } from "../../modules/debt-locker/contracts/interfaces/IDebtLocker.sol";

import { Borrower }     from "./accounts/Borrower.sol";
import { Keeper }       from "./accounts/Keeper.sol";
import { LP }           from "./accounts/LP.sol";
import { PoolDelegate } from "./accounts/PoolDelegate.sol";

import { IPoolLibLike, IStakeLockerLike } from "../interfaces/Interfaces.sol";

import { UniswapV2Strategy } from "../../modules/liquidations/contracts/UniswapV2Strategy.sol";

import { ChainlinkOracle } from "../../modules/chainlink-oracle/contracts/ChainlinkOracle.sol";

import { IBPoolLike, IBPoolFactoryLike, IERC20Like, Vm, ILoanInitializerLike, IMapleGlobalsLike, IPoolLike } from "../interfaces/Interfaces.sol";

import { AddressRegistry } from "../AddressRegistry.sol";

contract WethSimulation is AddressRegistry, StateManipulations, TestUtils {

    uint256 constant BTC = 10 ** 8;
    uint256 constant USD = 10 ** 6;
    uint256 constant WAD = 10 ** 18;

    IERC20Like constant mpl   = IERC20Like(MPL);
    IERC20Like constant wbtc = IERC20Like(WBTC);
    IERC20Like constant weth  = IERC20Like(WETH);
    IBPoolLike constant bPool = IBPoolLike(BPOOL);

    Vm constant vm = Vm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);

    IPoolLike    pool;
    PoolDelegate poolDelegate;

    uint256 start;

    function setUp() public {
        start = block.timestamp;
        _setUpMapleWethPool();
    }

    function test_fundLoan() external {

        // Deposit to pool
        erc20_mint(WETH, 3, address(this), 20_000 ether);
        weth.approve(address(pool), 20_000 ether);
        pool.deposit(20_000 ether);

        Borrower borrower = new Borrower();

        IMapleLoan loan = IMapleLoan(_createLoan(borrower, 0, 10_000 ether));

        // WETH before state
        assertEq(weth.balanceOf(pool.liquidityLocker()), 20_000 ether);
        assertEq(weth.balanceOf(address(loan)),          0);
        assertEq(weth.balanceOf(address(poolDelegate)),  0);
        assertEq(weth.balanceOf(MAPLE_TREASURY),         0);

        // Pool before state
        assertEq(pool.principalOut(), 0);
        assertEq(pool.interestSum(),  0);
        assertEq(pool.poolLosses(),   0);
        assertEq(pool.totalSupply(),  20_000 ether);
        _assertPoolInvariant();
        _assertStakeLockerInvariants();

        // Loan before state
        assertEq(loan.drawableFunds(),      0);
        assertEq(loan.nextPaymentDueDate(), 0);
        assertEq(loan.lender(),             address(0));

        poolDelegate.fundLoan(address(pool), address(loan), DL_FACTORY, 10_000 ether);

        // WETH after state
        assertEq(weth.balanceOf(pool.liquidityLocker()), 10_000 ether);
        assertEq(weth.balanceOf(address(loan)),          9975.589041095890410960 ether);  // 10k - estab fees
        assertEq(weth.balanceOf(address(poolDelegate)),  8.136986301369863013 ether);     // 10k * 90/365 * 0.33%
        assertEq(weth.balanceOf(MAPLE_TREASURY),         16.273972602739726027 ether);    // 10k * 90/365 * 0.66%

        // Pool after state
        assertEq(pool.principalOut(), 10_000 ether);
        assertEq(pool.interestSum(),  0);
        assertEq(pool.poolLosses(),   0);
        assertEq(pool.totalSupply(),  20_000 ether);
        _assertPoolInvariant();
        _assertStakeLockerInvariants();

        // Loan after state
        assertEq(loan.drawableFunds(),      9975.589041095890410960 ether);
        assertEq(loan.nextPaymentDueDate(), start + 30 days);
        assertEq(loan.lender(),             pool.debtLockers(address(loan), DL_FACTORY));
    }

    function test_loan_endToEnd() external {

        // Deposit to pool
        erc20_mint(WETH, 3, address(this), 20_000 ether);
        weth.approve(address(pool), 20_000 ether);
        pool.deposit(20_000 ether);

        /********************************/
        /*** Create and drawdown loan ***/
        /********************************/

        Borrower borrower = new Borrower();

        IMapleLoan loan = IMapleLoan(_createLoan(borrower, 0, 10_000 ether));

        _fundLoanAndDrawdown(borrower, address(loan), 10_000 ether);

        _assertPoolInvariant();
        _assertStakeLockerInvariants();

        /********************************/
        /*** Make Payment 1 (On time) ***/
        /********************************/

        vm.warp(loan.nextPaymentDueDate());

        ( uint256 principalPortion, uint256 interestPortion ) = loan.getNextPaymentBreakdown();

        assertEq(principalPortion, 0);
        assertEq(interestPortion,  98.63013698630136 ether);

        assertEq(weth.balanceOf(address(loan)), 0);

        // Make first payment
        erc20_mint(WETH, 3, address(borrower),      interestPortion);
        borrower.erc20_approve(WETH, address(loan), interestPortion);
        borrower.loan_makePayment(address(loan),    interestPortion);

        assertEq(weth.balanceOf(address(loan)), interestPortion);

        /************************************/
        /*** Claim Funds as Pool Delegate ***/
        /************************************/

        uint256 poolDelegateBal = 8.136986301369863013 ether;  // From establishmentFee

        assertEq(pool.principalOut(),                    10_000 ether);
        assertEq(pool.interestSum(),                     0);
        assertEq(weth.balanceOf(pool.liquidityLocker()), 10_000 ether);
        assertEq(weth.balanceOf(pool.stakeLocker()),     0);
        assertEq(weth.balanceOf(address(poolDelegate)),  poolDelegateBal);

        uint256[7] memory details = poolDelegate.claim(address(pool), address(loan), address(DL_FACTORY));

        _assertPoolInvariant();
        _assertStakeLockerInvariants();

        assertEq(weth.balanceOf(address(loan)), 0);

        assertEq(details[0], interestPortion);
        assertEq(details[1], interestPortion);
        assertEq(details[2], 0);
        assertEq(details[3], 0);
        assertEq(details[4], 0);
        assertEq(details[5], 0);
        assertEq(details[6], 0);

        assertEq(pool.principalOut(),                    10_000 ether);
        assertEq(pool.interestSum(),                     interestPortion * 80/100);                    // 80% of interest
        assertEq(weth.balanceOf(pool.liquidityLocker()), interestPortion * 80/100 + 10_000 ether);     // 80% of interest
        assertEq(weth.balanceOf(pool.stakeLocker()),     interestPortion * 10/100);                    // 10% of interest
        assertEq(weth.balanceOf(address(poolDelegate)),  poolDelegateBal + interestPortion * 10/100);  // 10% of interest

        /********************************/
        /*** Make Payment 2 (On time) ***/
        /********************************/

        vm.warp(loan.nextPaymentDueDate());

        assertEq(weth.balanceOf(address(loan)), 0);

        // Make second payment
        erc20_mint(WETH, 3, address(borrower),      interestPortion);
        borrower.erc20_approve(WETH, address(loan), interestPortion);
        borrower.loan_makePayment(address(loan),    interestPortion);

        assertEq(weth.balanceOf(address(loan)), interestPortion);

        /******************************/
        /*** Make Payment 3 (Final) ***/
        /******************************/

        vm.warp(loan.nextPaymentDueDate());

        ( principalPortion, interestPortion ) = loan.getNextPaymentBreakdown();

        assertEq(principalPortion, 10_000 ether);
        assertEq(interestPortion,  98.63013698630136 ether);

        assertEq(weth.balanceOf(address(loan)), interestPortion);

        // Make third payment
        erc20_mint(WETH, 3, address(borrower),      principalPortion + interestPortion);
        borrower.erc20_approve(WETH, address(loan), principalPortion + interestPortion);
        borrower.loan_makePayment(address(loan),    principalPortion + interestPortion);

        assertEq(weth.balanceOf(address(loan)), principalPortion + interestPortion * 2);

        /***************************************************/
        /*** Claim Funds as Pool Delegate (Two Payments) ***/
        /***************************************************/

        details = poolDelegate.claim(address(pool), address(loan), address(DL_FACTORY));

        _assertPoolInvariant();
        _assertStakeLockerInvariants();

        assertEq(weth.balanceOf(address(loan)), 0);

        assertEq(details[0], principalPortion + interestPortion * 2);
        assertEq(details[1], interestPortion * 2);
        assertEq(details[2], principalPortion);
        assertEq(details[3], 0);
        assertEq(details[4], 0);
        assertEq(details[5], 0);
        assertEq(details[6], 0);

        uint256 totalNetInterest = interestPortion * 80/100 * 3;

        assertEq(pool.principalOut(),                    0);
        assertEq(pool.interestSum(),                     totalNetInterest);
        assertEq(weth.balanceOf(pool.liquidityLocker()), 20_000 ether + totalNetInterest);
        assertEq(weth.balanceOf(pool.stakeLocker()),     interestPortion * 10/100 * 3);
        assertEq(weth.balanceOf(address(poolDelegate)),  poolDelegateBal + interestPortion * 10/100 * 3);
    }

    function test_triggerDefault_underCollateralized() external {

        // Deposit to pool
        erc20_mint(WETH, 3, address(this), 20_000 ether);
        weth.approve(address(pool), 20_000 ether);
        pool.deposit(20_000 ether);

        /********************************/
        /*** Create and drawdown loan ***/
        /********************************/

        Borrower borrower = new Borrower();

        IMapleLoan loan = IMapleLoan(_createLoan(borrower, 2 * BTC, 10_000 ether));

        _fundLoanAndDrawdown(borrower, address(loan), 10_000 ether);

        _assertPoolInvariant();
        _assertStakeLockerInvariants();

        /********************************/
        /*** Make Payment 1 (On time) ***/
        /********************************/

        vm.warp(loan.nextPaymentDueDate());

        // Check details for upcoming payment #1
        ( , uint256 interestPortion ) = loan.getNextPaymentBreakdown();
        erc20_mint(WETH, 3, address(borrower), interestPortion);

        borrower.erc20_approve(WETH, address(loan), interestPortion);
        borrower.loan_makePayment(address(loan), interestPortion);

        /*******************************/
        /*** Borrower Misses Payment ***/
        /*******************************/

        vm.warp(loan.nextPaymentDueDate() + loan.gracePeriod() + 1);

        /**************************************/
        /*** Pool Delegate triggers default ***/
        /**************************************/

        IDebtLocker debtLocker = IDebtLocker(pool.debtLockers(address(loan), address(DL_FACTORY)));

        vm.expectRevert("DL:TD:NEED_TO_CLAIM");
        poolDelegate.triggerDefault(address(pool),address(loan), address(DL_FACTORY));
        poolDelegate.claim(address(pool),address(loan), address(DL_FACTORY));

        _assertPoolInvariant();
        _assertStakeLockerInvariants();

        // DebtLocker before state
        assertTrue( debtLocker.liquidator() == address(0));
        assertTrue(!debtLocker.repossessed());

        // WETH/WBTC before tate
        assertEq(weth.balanceOf(address(loan)),       0);
        assertEq(weth.balanceOf(address(debtLocker)), 0);
        assertEq(wbtc.balanceOf(address(loan)),       2 * BTC);
        assertEq(wbtc.balanceOf(address(debtLocker)), 0);

        poolDelegate.triggerDefault(address(pool),address(loan), address(DL_FACTORY));

        // IDebtLocker after state
        assertTrue(debtLocker.liquidator() != address(0));
        assertTrue(debtLocker.repossessed());

        // WETH/WBTC after state
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

        assertEq(wbtc.balanceOf(address(debtLocker.liquidator())), 0);

        /***************************************************************/
        /*** Pool delegate claims funds, triggering BPT burning flow ***/
        /***************************************************************/

        IStakeLockerLike stakeLocker = IStakeLockerLike(pool.stakeLocker());

        uint256 swapOutAmount = IPoolLibLike(POOL_LIB).getSwapOutValueLocker(address(bPool), WETH, address(stakeLocker));

        assertEq(swapOutAmount, 1.333333333333333336 ether);  // 8 ether / 6

        uint256 totalRecoveredFromLiquidation = 28.943281253299445402 ether;

        uint256 bPool_stakeLockerBal    = bPool.balanceOf(pool.stakeLocker());
        uint256 weth_liquidityLockerBal = weth.balanceOf(pool.liquidityLocker());

        assertEq(bPool.balanceOf(pool.stakeLocker()),    99.99 ether);
        assertEq(weth.balanceOf(pool.liquidityLocker()), 10_078.904109589041088 ether);
        assertEq(weth.balanceOf(address(debtLocker)),    totalRecoveredFromLiquidation);
        assertEq(pool.principalOut(),                    10_000 ether);
        assertEq(pool.interestSum(),                     78.904109589041088 ether);
        assertEq(pool.poolLosses(),                      0);
        assertEq(stakeLocker.fundsTokenBalance(),        9.863013698630136 ether);
        assertEq(stakeLocker.bptLosses(),                0);

        uint256[7] memory details = poolDelegate.claim(address(pool),address(loan), address(DL_FACTORY));

        _assertPoolInvariant();
        _assertStakeLockerInvariants();

        assertEq(details[0], totalRecoveredFromLiquidation);
        assertEq(details[1], 0);
        assertEq(details[2], 0);
        assertEq(details[3], 0);
        assertEq(details[4], 0);
        assertEq(details[5], totalRecoveredFromLiquidation);
        assertEq(details[6], 10_000 ether - totalRecoveredFromLiquidation);

        assertEq(bPool.balanceOf(pool.stakeLocker()),    81.6396478879661565 ether);  // Roughly 5/6 of original amount
        assertEq(weth.balanceOf(pool.liquidityLocker()), 10_109.180724175673866738 ether);
        assertEq(weth.balanceOf(pool.liquidityLocker()), weth_liquidityLockerBal + totalRecoveredFromLiquidation + swapOutAmount);
        assertEq(weth.balanceOf(address(debtLocker)),    0);
        assertEq(pool.principalOut(),                    0);
        assertEq(pool.interestSum(),                     78.904109589041088 ether);
        assertEq(pool.poolLosses(),                      9_969.723385413367221262 ether);
        assertEq(pool.poolLosses(),                      10_000 ether - totalRecoveredFromLiquidation - swapOutAmount);
        assertEq(stakeLocker.fundsTokenBalance(),        9.863013698630136 ether);
        assertEq(stakeLocker.bptLosses(),                18.3503521120338435 ether);  // Roughly 1/6 of original amount

        assertEq(bPool_stakeLockerBal - bPool.balanceOf(pool.stakeLocker()), stakeLocker.bptLosses());
    }

    function test_poolFDT_multiUser_interestAndLosses() external {
        Borrower borrower = new Borrower();

        LP lp1 = new LP();
        LP lp2 = new LP();

        erc20_mint(WETH, 3, address(lp1), 20_000 ether);
        erc20_mint(WETH, 3, address(lp2), 30_000 ether);
        lp1.approve(WETH, address(pool), 20_000 ether);
        lp2.approve(WETH, address(pool), 30_000 ether);
        lp1.deposit(address(pool), 20_000 ether);  // 40% equity
        lp2.deposit(address(pool), 30_000 ether);  // 60% equity

        /**************************************************/
        /*** Create and drawdown loan, make one payment ***/
        /**************************************************/

        IMapleLoan loan = IMapleLoan(_createLoan(borrower, 2 * BTC, 10_000 ether));
        _fundLoanAndDrawdown(borrower, address(loan), 10_000 ether);
        vm.warp(loan.nextPaymentDueDate());

        ( , uint256 interestPortion ) = _makePayment(address(loan), address(borrower));
        assertEq(interestPortion, 98.63013698630136 ether);

        /************************************************/
        /*** Pool claims funds, distributing interest ***/
        /************************************************/

        uint256 netInterest = interestPortion * 80/100;  // Net of ongoing fees

        assertEq(pool.interestSum(),                     0);
        assertEq(pool.withdrawableFundsOf(address(lp1)), 0);
        assertEq(pool.withdrawableFundsOf(address(lp2)), 0);

        poolDelegate.claim(address(pool),address(loan), address(DL_FACTORY));

        assertEq(pool.interestSum(), netInterest);

        assertWithinDiff(pool.withdrawableFundsOf(address(lp1)), netInterest * 40/100, 1);
        assertWithinDiff(pool.withdrawableFundsOf(address(lp2)), netInterest * 60/100, 1);

        /**********************************/
        /*** LP2 deposits, LP3 deposits ***/
        /**********************************/

        LP lp3 = new LP();

        erc20_mint(WETH, 3, address(lp2), 20_000 ether);
        erc20_mint(WETH, 3, address(lp3), 30_000 ether);
        lp2.approve(WETH, address(pool), 20_000 ether);
        lp3.approve(WETH, address(pool), 30_000 ether);
        lp2.deposit(address(pool), 20_000 ether);  // 50% equity
        lp3.deposit(address(pool), 30_000 ether);  // 30% equity, LP1 now at 20% equity

        // New deposits have no impact on previous interest earnings
        assertWithinDiff(pool.withdrawableFundsOf(address(lp1)), netInterest * 40/100, 1);
        assertWithinDiff(pool.withdrawableFundsOf(address(lp2)), netInterest * 60/100, 1);

        assertEq(pool.withdrawableFundsOf(address(lp3)), 0);

        /****************************************************/
        /*** Make another payment and distribute interest ***/
        /****************************************************/

        _makePayment(address(loan), address(borrower));  // Same interestPortion

        poolDelegate.claim(address(pool),address(loan), address(DL_FACTORY));

        assertEq(pool.interestSum(), netInterest * 2);

        assertWithinDiff(pool.withdrawableFundsOf(address(lp1)), (netInterest * 40/100) + (netInterest * 20/100), 1);
        assertWithinDiff(pool.withdrawableFundsOf(address(lp2)), (netInterest * 60/100) + (netInterest * 50/100), 1);
        assertWithinDiff(pool.withdrawableFundsOf(address(lp3)), (netInterest *  0/100) + (netInterest * 30/100), 1);

        /**************************************/
        /*** Pool Delegate triggers default ***/
        /**************************************/

        assertEq(pool.poolLosses(),                       0);
        assertEq(pool.recognizableLossesOf(address(lp1)), 0);
        assertEq(pool.recognizableLossesOf(address(lp2)), 0);
        assertEq(pool.recognizableLossesOf(address(lp3)), 0);

        // Trigger default
        vm.warp(loan.nextPaymentDueDate() + loan.gracePeriod() + 1);
        poolDelegate.triggerDefault(address(pool),address(loan), address(DL_FACTORY));

        // Liquidate collateral
        IDebtLocker       debtLocker        = IDebtLocker(pool.debtLockers(address(loan), address(DL_FACTORY)));
        Keeper            keeper1           = new Keeper();
        UniswapV2Strategy uniswapV2Strategy = new UniswapV2Strategy();
        poolDelegate.debtLocker_setAllowedSlippage(address(debtLocker), 300);  // 3% slippage allowed
        _liquidate(keeper1, address(uniswapV2Strategy), debtLocker, 2 * BTC);
        assertEq(wbtc.balanceOf(address(debtLocker.liquidator())), 0);

        // Claim liquidated funds, burn BPTs, update accounting
        poolDelegate.claim(address(pool),address(loan), address(DL_FACTORY));

        // uint256 poolLosses = 9_969.723385413367221262 ether;
        uint256 poolLosses = 9_966.306924132935515573 ether;

        assertEq(pool.poolLosses(), poolLosses);
        assertWithinDiff(pool.recognizableLossesOf(address(lp1)), poolLosses * 20/100, 1);
        assertWithinDiff(pool.recognizableLossesOf(address(lp2)), poolLosses * 50/100, 1);
        assertWithinDiff(pool.recognizableLossesOf(address(lp3)), poolLosses * 30/100, 1);

        /************************/
        /*** All LPs withdraw ***/
        /************************/

        assertEq(weth.balanceOf(pool.liquidityLocker()), 100_000 ether + netInterest * 2 - poolLosses);

        vm.warp(block.timestamp + pool.lockupPeriod());

        lp1.intendToWithdraw(address(pool));
        lp2.intendToWithdraw(address(pool));
        lp3.intendToWithdraw(address(pool));

        ( uint256 cooldownPeriod, ) = IMapleGlobalsLike(MAPLE_GLOBALS).getLpCooldownParams();

        vm.warp(block.timestamp + cooldownPeriod);

        lp1.withdraw(address(pool), 20_000 ether);
        _assertPoolInvariant();
        lp2.withdraw(address(pool), 50_000 ether);
        _assertPoolInvariant();
        lp3.withdraw(address(pool), 30_000 ether);
        _assertPoolInvariant();

        assertWithinDiff(weth.balanceOf(pool.liquidityLocker()), 0, 1);

        assertWithinDiff(weth.balanceOf(address(lp1)), 20_000 ether + (netInterest * 40/100) + (netInterest * 20/100) - poolLosses * 20/100, 1);
        assertWithinDiff(weth.balanceOf(address(lp2)), 50_000 ether + (netInterest * 60/100) + (netInterest * 50/100) - poolLosses * 50/100, 1);
        assertWithinDiff(weth.balanceOf(address(lp3)), 30_000 ether + (netInterest *  0/100) + (netInterest * 30/100) - poolLosses * 30/100, 1);
    }

    /************************/
    /*** Helper Functions ***/
    /************************/

    function _assertPoolInvariant() internal {
        assertTrue(
            pool.totalSupply() + pool.interestSum() - pool.poolLosses() <=
            weth.balanceOf(pool.liquidityLocker()) + pool.principalOut()
        );
    }

    function _assertStakeLockerInvariants() internal {
        IStakeLockerLike stakeLocker = IStakeLockerLike(pool.stakeLocker());
        assertTrue(stakeLocker.totalSupply() - stakeLocker.bptLosses() <= bPool.balanceOf(address(stakeLocker)));
        assertTrue(stakeLocker.fundsTokenBalance() <= weth.balanceOf(address(stakeLocker)));
    }

     function _createLoan(Borrower borrower, uint256 collaretalRequired, uint256 principalRequested) internal returns (address loan) {
        address[2] memory assets = [WBTC, WETH];
        uint256[3] memory termDetails = [
            uint256(10 days),  // 10 day grace period
            uint256(30 days),  // 30 day payment interval
            uint256(3)
        ];

        uint256[3] memory requests = [collaretalRequired, principalRequested, principalRequested];
        uint256[4] memory rates    = [uint256(0.12e18), uint256(0), uint256(0), uint256(0.6e18)];

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

    function _makePayment(address loan, address borrower) internal returns (uint256 principalPortion, uint256 interestPortion) {
        ( principalPortion, interestPortion ) = IMapleLoan(loan).getNextPaymentBreakdown();

        uint256 total = principalPortion + interestPortion;

        erc20_mint(WETH, 3, address(borrower), total);
        Borrower(borrower).erc20_approve(WETH, loan, total);
        Borrower(borrower).loan_makePayment(loan, total);
    }

    function _setUpMapleWethPool() internal {

        /*********************/
        /*** Set up actors ***/
        /*********************/

        // Grant address(this) auth access to globals
        vm.store(MAPLE_GLOBALS, bytes32(uint256(1)), bytes32(uint256(uint160(address(this)))));

        poolDelegate = new PoolDelegate();

        /*************************/
        /*** Configure Globals ***/
        /*************************/

        IMapleGlobalsLike globals = IMapleGlobalsLike(MAPLE_GLOBALS);

        globals.setLiquidityAsset(WETH, true);
        globals.setPoolDelegateAllowlist(address(poolDelegate), true);
        // globals.setPriceOracle(WETH, address(ethOracle));
        globals.setSwapOutRequired(10_000);

        /*************************************/
        /*** Set up MPL/WETH Balancer Pool ***/
        /*************************************/

        emit log_named_uint("weth price", globals.getLatestPrice(WETH));

        erc20_mint(MPL,  0, address(this), 2250 ether);
        erc20_mint(WETH, 3, address(this), 17 ether);

        mpl.approve(address(bPool),  2250 ether);
        weth.approve(address(bPool), 17 ether);

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 2250 ether;
        amounts[1] = 17 ether;

        emit log_named_uint("weth.balanceOf(address(this))", weth.balanceOf(address(this)));
        emit log_named_uint("mpl.balanceOf(address(this)) ", mpl.balanceOf(address(this)));

        bPool.joinPool(47_000 ether, amounts);

        emit log_named_uint("weth.balanceOf(address(this))", weth.balanceOf(address(this)));
        emit log_named_uint("mpl.balanceOf(address(this)) ", mpl.balanceOf(address(this)));

        // Add to globals
        globals.setValidBalancerPool(address(bPool), true);

        // // Transfer max amount of burnable BPTs (Can't stake totalSupply)
        bPool.transfer(address(poolDelegate), 47_000 ether);  // Pool Delegate gets enought BPT to stake

        /********************************************************/
        /*** Set up new WETH liquidity pool, closed to public ***/
        /********************************************************/

        // Create a WETH pool with a 5m liquidity cap
        pool = IPoolLike(poolDelegate.createPool(POOL_FACTORY, WETH, address(bPool), SL_FACTORY, LL_FACTORY, 1000, 1000, 150_000 ether));

        // Stake BPT for insurance and finalize pool
        poolDelegate.approve(address(bPool), pool.stakeLocker(), type(uint256).max);
        poolDelegate.stake(pool.stakeLocker(), bPool.balanceOf(address(poolDelegate)));
        poolDelegate.finalize(address(pool));
        poolDelegate.setOpenToPublic(address(pool), true);
    }

}

