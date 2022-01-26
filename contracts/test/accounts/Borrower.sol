// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.7;

import { ERC20Like, LoanFactoryLike, LoanLike } from "../../interfaces/Interfaces.sol";

contract Borrower {

    function loan_makePayment(address loan_, uint256 amount_) external returns (uint256 totalPrincipalAmount_, uint256 totalInterestFees_) {
        return LoanLike(loan_).makePayment(amount_);
    }

    function loan_drawdownFunds(address loan_, uint256 amount_, address destination_) external returns (uint256 collateralPosted_) {
        return LoanLike(loan_).drawdownFunds(amount_, destination_);
    }

    function erc20_approve(address token, address account, uint256 amt) external {
        ERC20Like(token).approve(account, amt);
    }

     function try_mapleProxyFactory_createInstance(address factory_, bytes calldata arguments_, bytes32 salt_) external returns (bool ok_) {
        ( ok_, ) = factory_.call(abi.encodeWithSelector(LoanFactoryLike.createInstance.selector, arguments_, salt_));
    }

    function mapleProxyFactory_createInstance(address factory_, bytes calldata arguments_, bytes32 salt_) external returns (address instance_) {
        return LoanFactoryLike(factory_).createInstance(arguments_, salt_);
    }

}
