// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {console} from "forge-std/console.sol";
import {stdStorage, StdStorage, Test} from "forge-std/Test.sol";

import {Utils} from "./utils/Utils.sol";
import {Protection} from "../src/protection.sol";

import "./mocks/LinkToken.sol";
import "./mocks/MockOracle.sol";

/**
 * @title Gradient Protection (v0.1) unit tests
 * @author @cairoeth
 **/
contract BaseSetup is Protection, Test {
    Utils internal utils;
    address payable[] internal users;

    address internal gradient;
    address internal lender;

    Protection public protection_contract;
    LinkToken public linkToken;
    MockOracle public mockOracle;

    function setUp() public virtual {
        utils = new Utils();
        users = utils.createUsers(2);

        gradient = users[0];
        vm.label(gradient, "Gradient");
        lender = users[1];
        vm.label(lender, "Lender");

        vm.prank(gradient);
        protection_contract = new Protection();

        linkToken = new LinkToken();
        mockOracle = new MockOracle(address(linkToken));

        linkToken.transfer(address(protection_contract), 100000000000000000000);
    }
}

contract NFTfiAddress is BaseSetup {
    address internal nftfi_address = 0x33e75763F3705252775C5AEEd92E5B4987622f44;

    function setUp() public virtual override {
        BaseSetup.setUp();
    }

    function testNFTfiAddress() public {
        console.log(
            "Should establish the NFTfi address using the owner address"
        );

        /// Ensure tx sender is owner
        vm.prank(gradient);
        protection_contract.setNFTfiAddress(nftfi_address);
    }

    function testFailNFTfiAddress() public {
        console.log(
            "Should not establish the NFTfi address as the sender is not owner"
        );

        /// Ensure tx sender is owner
        vm.prank(address(0));
        protection_contract.setNFTfiAddress(nftfi_address);
    }
    
}

contract TriggerProtetion is BaseSetup {
    function setUp() public virtual override {
        BaseSetup.setUp();
    }

    function testRepayed() public {
        console.log(
            "Should establish the NFTfi address using the owner address"
        );
    }

    function testOptionA() public {
        console.log(
            "Should establish the NFTfi address using the owner address"
        );
    }

    function testOptionB() public {
        console.log(
            "Should establish the NFTfi address using the owner address"
        );
    }

    function testOptionC() public {
        console.log(
            "Should establish the NFTfi address using the owner address"
        );
    }
}
