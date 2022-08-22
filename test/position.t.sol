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

        gradient = address(0xD23a1F43571E32d55D521c5c3707Fb15AcFbF391);
        vm.label(gradient, "Gradient Deployer");
        user = utils.createUsers(1)[0];
        vm.label(user, "User");

        linkToken = new LinkToken();
        mockOracle = new MockOracle(address(linkToken));

        vm.prank(gradient);
        position_contract = new Position(address(linkToken), address(mockOracle));

        linkToken.transfer(address(position_contract), 100000000000000000000);
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
