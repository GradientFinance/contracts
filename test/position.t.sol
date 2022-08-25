// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {console} from "forge-std/console.sol";
import {stdStorage, StdStorage, Test} from "forge-std/Test.sol";

import {Utils} from "./utils/Utils.sol";
import "../src/position.sol";

import "./mocks/LinkToken.sol";
import "./mocks/MockOracle.sol";

/**
 * @title Gradient (v0.2) unit tests
 * @author @cairoeth
 **/
contract BaseSetup is Test {
    Utils internal utils;

    address internal gradient;
    address internal user;

    Position public position_contract;
    LinkToken public linkToken;
    MockOracle public mockOracle;

    function setUp() public virtual {
        utils = new Utils();

        gradient = address(0xe7E60d2d6D7dF39810eE973Ae6187b01D4758344);
        vm.label(gradient, "Gradient Deployer");
        vm.deal(gradient, 10000 ether);

        user = utils.createUsers(1)[0];
        vm.label(user, "User");

        linkToken = new LinkToken();
        mockOracle = new MockOracle(address(linkToken));

        vm.prank(gradient);
        position_contract = new Position(address(linkToken), address(mockOracle));

        linkToken.transfer(address(position_contract), 100000000000000000000);
    }
}


contract TestMintPosition is BaseSetup {
    function setUp() public virtual override {
        BaseSetup.setUp();
    }

    function testMintLong() public {
        console.log(
            "Mint a long position with correct signature and parameters."
        );

        uint256 _margin = 5000000000000000000;
        uint32 _nftfId = 8395;
        bool position = true;
        uint256 _leverage = 1000000000000000000;
        uint256 _premium = 908438124943164160;
        uint256 _expiryUnix = 0;
        uint256 _repayment = 12400000000000000000;

        vm.prank(user);
        position_contract.mintPosition{ value: _margin }(
            _nftfId,  // _nftfId (uint32)
            position,  // _position (bool)
            _leverage,  // _leverage (uint256)
            _premium,  // _premium (uint256)
            _expiryUnix,  // _expiryUnix (uint256)
            _repayment,   // _repayment (uint256)
            "0x505b348212c583c84f1fa81b2a8121f9e4cc5f71dcf6d428856a0a96324109626a1bbb18ab4c368b37e6857826b701e6fc899aff5efcd3306d7c301514aa8cef1c"  // _signature (bytes)
        );
    }
}


contract TestWithdraw is BaseSetup {
    function setUp() public virtual override {
        BaseSetup.setUp();
    }

    function testWithdrawLink() public {
        console.log(
            "Withdraw link from the smart contract as owner."
        );

        vm.prank(gradient);
        position_contract.withdrawLink();

        assertEq(0, linkToken.balanceOf(address(position_contract)));
    }

    function testFailWithdrawLink() public {
        console.log(
            "Should not withdraw link from the smart contract."
        );

        vm.prank(address(0));
        position_contract.withdrawLink();
    }
}
