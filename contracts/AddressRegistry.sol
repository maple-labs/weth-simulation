// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.7;

contract AddressRegistry {

    /**************************/
    /*** External Contracts ***/
    /**************************/

    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address constant WBTC = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;

    address constant BPOOL_FACTORY  = 0x9424B1412450D0f8Fc2255FAf6046b98213B76Bd;
    address constant ETH_USD_ORACLE = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;

    /***********************************/
    /*** Deployed Protocol Contracts ***/
    /***********************************/

    address constant GOVERNOR         = 0xd6d4Bcde6c816F17889f1Dd3000aF0261B03a196;
    address constant MPL              = 0x33349B282065b0284d756F0577FB39c158F935e6;
    address constant BALANCER_POOL    = 0xc1b10e536CD611aCFf7a7c32A9E29cE6A02Ef6ef;
    address constant MAPLE_GLOBALS    = 0xC234c62c8C09687DFf0d9047e40042cd166F3600;
    address constant MAPLE_TREASURY   = 0xa9466EaBd096449d650D5AEB0dD3dA6F52FD0B19;
    address constant POOL_FACTORY     = 0x2Cd79F7f8b38B9c0D80EA6B230441841A31537eC;
    address constant POOL_LIB         = 0x2c1C30fb8cC313Ef3cfd2E2bBf2da88AdD902C30;
    address constant LOAN_FACTORY     = 0x36a7350309B2Eb30F3B908aB0154851B5ED81db0;
    address constant LOAN_INITIALIZER = 0xCba99a6648450a7bE7f20B1C3258F74Adb662020;
    address constant DL_FACTORY       = 0xA83404CAA79989FfF1d84bA883a1b8187397866C;
    address constant SL_FACTORY       = 0x53a597A4730Eb02095dD798B203Dcc306348B8d6;
    address constant LL_FACTORY       = 0x966528BB1C44f96b3AA8Fbf411ee896116b068C9;

}
