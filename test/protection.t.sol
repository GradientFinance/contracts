// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {console} from "forge-std/console.sol";
import {stdStorage, StdStorage, Test} from "forge-std/Test.sol";

import {Utils} from "./utils/Utils.sol";
import {Protection} from "../src/protection.sol";

/**
 * @title Gradient Protection (v0.1) unit tests
 * @author @cairoeth
 **/
contract BaseSetup is Protection, Test {
    Utils internal utils;
    address payable[] internal users;

    address internal gradient;
    address internal lender;

    Protection protection_contract;

    function setUp() public virtual {
        utils = new Utils();
        users = utils.createUsers(2);

        gradient = users[0];
        vm.label(gradient, "Gradient");
        lender = users[1];
        vm.label(lender, "Lender");

        vm.prank(gradient);
        protection_contract = new Protection();
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

contract ChainlinkSetup is BaseSetup {
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
