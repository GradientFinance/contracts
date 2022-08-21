// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {console} from "forge-std/console.sol";
import {stdStorage, StdStorage, Test} from "forge-std/Test.sol";

import {Utils} from "./utils/Utils.sol";
import {Position} from "../src/position.sol";

import "./mocks/LinkToken.sol";
import "./mocks/MockOracle.sol";

/**
 * @title Gradient (v0.2) unit tests
 * @author @cairoeth
 **/
contract BaseSetup is Position, Test {
    Utils internal utils;
    address payable[] internal users;

    address internal gradient;
    address internal user;

    Position public position_contract;
    LinkToken public linkToken;
    MockOracle public mockOracle;

    function setUp() public virtual {
        utils = new Utils();
        users = utils.createUsers(2);

        gradient = address(0xD23a1F43571E32d55D521c5c3707Fb15AcFbF391);
        vm.label(gradient, "Gradient Deployer");
        user = users[1];
        vm.label(user, "User");

        linkToken = new LinkToken();
        mockOracle = new MockOracle(address(linkToken));

        vm.prank(gradient);
        position_contract = new Position(address(linkToken), address(mockOracle));

        linkToken.transfer(address(position_contract), 100000000000000000000);
    }
}

// contract TestWithdraw is BaseSetup {
//     function setUp() public virtual override {
//         BaseSetup.setUp();
//     }

//     function testWithdrawLink() public {
//         console.log(
//             "Withdraw link from the smart contract as owner."
//         );

//         console.log(position_contract.owner());
//         console.log(linkToken.balanceOf(address(position_contract)));

//         vm.prank(gradient);
//         position_contract.withdrawLink();

//         console.log(linkToken.balanceOf(address(position_contract)));
//     }

//     function testFailWithdrawLink() public {
//         console.log(
//             "Should not withdraw link from the smart contract."
//         );

//         /// Ensure tx sender is not owner
//         vm.prank(address(0));
//         position_contract.withdrawLink();
//     }
// }


// contract TestMintPositions is BaseSetup {
//     function setUp() public virtual override {
//         BaseSetup.setUp();
//     }

//     function testMintLong() public {
//         console.log(
//             "Mint a long position to test the signature and parameters."
//         );

//         vm.prank(user);
//         position_contract.mintPosition{ value: 4500000000000000000 }(
//             9292,  // _nftfId (uint32)
//             true,  // _position (bool)
//             1000000000000000000,  // _leverage (uint256)
//             15131683487736830,  // _premium (uint256)
//             1662153129,  // _expiryUnix (uint256)
//             4500000000000000000,   // _principal (uint256)
//             "0x5698c1485b8b4898696acd75db44e7bb55a5501d1123c9726b46e6e3f3423a6763dcf34e45b80897e5425d881de3f32474e814072ba37b17a22eb8c7a626348f1b"  // _signature (bytes)
//         );
    
//     }
// }
