// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {console} from "forge-std/console.sol";
import {stdStorage, StdStorage, Test} from "forge-std/Test.sol";

import {Utils} from "./utils/Utils.sol";
import {Protection} from "../src/protection.sol";

import "./mocks/LinkToken.sol";
import "./mocks/MockOracle.sol";
import "./mocks/MockNFTfi.sol";

/**
 * @title Gradient Protection (v0.1) unit tests
 * @author @cairoeth
 **/
contract BaseSetup is Protection, Test {
    Utils internal utils;
    address payable[] internal users;

    address internal gradient;
    address internal lender;
    address internal nftfi_address;

    Protection public protection_contract;
    LinkToken public linkToken;
    MockOracle public mockOracle;
    IDirectLoanBase public nftcontract;

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
        nftcontract = new IDirectLoanBase();

        linkToken.transfer(address(protection_contract), 100000000000000000000);
        nftfi_address = address(nftcontract);
    }
}

contract NFTfiAddress is BaseSetup {
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

contract TriggerProtetionRepayed is BaseSetup {
    function setUp() public virtual override {
        BaseSetup.setUp();
        vm.prank(gradient);
        protection_contract.setNFTfiAddress(nftfi_address);

        /// Ensure tx sender is owner
        vm.prank(gradient);

        /// Assuming collateral floor is 3 eth, hence testing with protection for 50% to 70%. Staking is 3 eth.
        protection_contract.mintProtection{ value: 3000000000000000000 }(
            lender,
            9999,
            1500000000000000000,
            2100000000000000000,
            1658243723,
            0, /// Unix timestamp is 0 to trigger the block.timestamp check
            0xf5de760f2e916647fd766B4AD9E85ff943cE3A2b,
            1261495
        );
    }

    function testRepayed() public {
        console.log(
            "Mint a protection to trigger the protection simulating the loan is repaid."
        );
    
    }
}
