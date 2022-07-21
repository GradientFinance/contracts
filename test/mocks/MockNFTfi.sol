// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

contract IDirectLoanBase {

    function loanRepaidOrLiquidated(uint32) external view returns (bool) {
        return true;
    }
}
