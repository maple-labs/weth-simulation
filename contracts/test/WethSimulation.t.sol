// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.7;

import { TestUtils, StateManipulations } from "../../modules/contract-test-utils/contracts/test.sol";

import { Borrower }     from "./accounts/Borrower.sol";
import { PoolDelegate } from "./accounts/PoolDelegate.sol";

import { WETHOracleMock } from "./mocks/Mocks.sol"; 

import { BPoolLike, BPoolFactoryLike, ERC20Like, Hevm, LoanLike, MapleGlobalsLike, PoolLike } from "../interfaces/Interfaces.sol";

import { AddressRegistry } from "../AddressRegistry.sol";

contract WethSimulation is AddressRegistry, StateManipulations, TestUtils {

    uint256 constant WAD = 10 ** 18;
    uint256 constant RAY = 10 ** 27;
    uint256 constant RAD = 10 ** 45;

    address[3] calcs;

    ERC20Like constant weth = ERC20Like(WETH);
    ERC20Like constant mpl = ERC20Like(MPL);

    PoolDelegate   poolDelegate;
    PoolLike       pool;
    WETHOracleMock oracleMock;

    uint256 start;

    function setUp() public {

        start = block.timestamp;

        calcs = [REPAYMENT_CALC, LATEFEE_CALC, PREMIUM_CALC];

        oracleMock = new WETHOracleMock();

        _setUpMapleWethPool();
    }

    function test_basic_e2eLoan() external {

        Borrower borrower = new Borrower();

        LoanLike loan = LoanLike(_createLoan(borrower, [1000, 180, 30, uint256(1_000_000 * WAD), 2000]));

        _fundLoanAndDrawdown(borrower, address(loan), 1_000_000 * WAD);

        hevm.warp(start + 30 days);

        _makePayment(address(loan), address(borrower));

        /********************************/
        /*** Claim Interest into Pool ***/
        /********************************/


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

        //mint to pool
        erc20_mint(WETH, 3, address(pool), 1e26);
        emit log_named_uint("bal", ERC20Like(WETH).balanceOf(address(pool)));
    }

     function _createLoan(Borrower borrower, uint256[5] memory specs) internal returns (address loan) {
        return borrower.createLoan(LOAN_FACTORY, WETH, WBTC, FL_FACTORY, CL_FACTORY, specs, calcs);
    }

    function _fundLoanAndDrawdown(Borrower borrower, address loan, uint256 fundAmount) internal {
        poolDelegate.fundLoan(address(pool), loan, DL_FACTORY, fundAmount);

        uint256 collateralRequired = LoanLike(loan).collateralRequiredForDrawdown(fundAmount);

        if (collateralRequired > 0) {
            erc20_mint(WBTC, 0, address(borrower), collateralRequired);
            borrower.approve(WBTC, loan, collateralRequired);
        }
        
        borrower.drawdown(loan, fundAmount);
    }

    function _makePayment(address loan, address borrower) internal {
        ( uint256 paymentAmount, , ) = LoanLike(loan).getNextPayment();
        erc20_mint(WETH, 3, address(borrower), paymentAmount);
        Borrower(borrower).approve(WETH, loan, paymentAmount);
        Borrower(borrower).makePayment(loan);
    }
}

