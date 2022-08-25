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
    uint256 privateKey = 0xBEEF;

    Position public position_contract;
    LinkToken public linkToken;
    MockOracle public mockOracle;

    function setUp() public virtual {
        utils = new Utils();

        gradient = vm.addr(privateKey);
        vm.label(gradient, "Gradient Deployer");
        vm.deal(gradient, 10000 ether);

        user = utils.createUsers(1)[0];
        vm.label(user, "User");

        linkToken = new LinkToken();
        mockOracle = new MockOracle(address(linkToken));

        vm.prank(gradient);
        position_contract = new Position(address(linkToken), address(mockOracle));

        (bool sent, ) = address(position_contract).call{value: 100 ether}("");
        require(sent, "Failed to send Ether");

        linkToken.transfer(address(position_contract), 100000000000000000000);
    }
}

contract TestLongSignature is BaseSetup {
    uint256 _margin = 5000000000000000000;  // 5 ETH
    uint32 _nftfId = 8395;
    bool _position = true;  // Long position
    uint256 _leverage = 1000000000000000000;  // x1
    uint256 _premium = 908438124943164160;  // 0.908 ETH
    uint256 _expiryUnix = 1663700471;  // 20 September 2022
    uint256 _repayment = 13090000000000000000;  // 13.09 ETH

    function setUp() public virtual override {
        BaseSetup.setUp();
    }

    function testLongSignature() public {
        console.log(
            "Mint a long position with correct signature and parameters."
        );

        bytes32 hash = keccak256(abi.encodePacked(_margin, _nftfId, _position, _leverage, _premium, _expiryUnix, _repayment));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, hash);

        vm.prank(user);
        position_contract.mintPosition{ value: _margin }(
            _nftfId,  // _nftfId (uint32)
            _position,  // _position (bool)
            _leverage,  // _leverage (uint256)
            _premium,  // _premium (uint256)
            _expiryUnix,  // _expiryUnix (uint256)
            _repayment,   // _repayment (uint256)
            v,  // v (uint8)
            r,  // r (bytes32)
            s  // s (bytes32)
        );

        assertEq(position_contract.balanceOf(user), 1);
        assertEq(position_contract.ownerOf(1), user);
    }

    function testFailLongSignature() public {
        console.log(
            "Mint a long position with incorrect signature and parameters."
        );

        bytes32 hash = keccak256(abi.encodePacked(_margin, _nftfId, _position, _leverage, _premium, _expiryUnix, _repayment));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, hash);

        vm.prank(user);
        position_contract.mintPosition{ value: _margin }(
            1111,  // _nftfId (uint32)
            _position,  // _position (bool)
            _leverage,  // _leverage (uint256)
            _premium,  // _premium (uint256)
            _expiryUnix,  // _expiryUnix (uint256)
            _repayment,   // _repayment (uint256)
            v,  // v (uint8)
            r,  // r (bytes32)
            s  // s (bytes32)
        );
    }
}

contract TestShortSignature is BaseSetup {
    uint256 _margin = 5000000000000000000;  // 5 ETH
    uint32 _nftfId = 8395;
    bool _position = false;  // Short position
    uint256 _leverage = 1000000000000000000;  // x1
    uint256 _premium = 908438124943164160;  // 0.908 ETH
    uint256 _expiryUnix = 1663700471;  // 20 September 2022
    uint256 _repayment = 13090000000000000000;  // 13.09 ETH

    function setUp() public virtual override {
        BaseSetup.setUp();
    }

    function testShortSignature() public {
        console.log(
            "Mint a short position with correct signature and parameters."
        );

        bytes32 hash = keccak256(abi.encodePacked(_margin, _nftfId, _position, _leverage, _premium, _expiryUnix, _repayment));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, hash);

        vm.prank(user);
        position_contract.mintPosition{ value: _margin }(
            _nftfId,  // _nftfId (uint32)
            _position,  // _position (bool)
            _leverage,  // _leverage (uint256)
            _premium,  // _premium (uint256)
            _expiryUnix,  // _expiryUnix (uint256)
            _repayment,   // _repayment (uint256)
            v,  // v (uint8)
            r,  // r (bytes32)
            s  // s (bytes32)
        );

        assertEq(position_contract.balanceOf(user), 1);
        assertEq(position_contract.ownerOf(1), user);
    }

    function testFailShortSignature() public {
        console.log(
            "Mint a short position with incorrect signature and parameters."
        );

        bytes32 hash = keccak256(abi.encodePacked(_margin, _nftfId, _position, _leverage, _premium, _expiryUnix, _repayment));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, hash);

        vm.prank(user);
        position_contract.mintPosition{ value: _margin }(
            1111,  // _nftfId (uint32)
            _position,  // _position (bool)
            _leverage,  // _leverage (uint256)
            _premium,  // _premium (uint256)
            _expiryUnix,  // _expiryUnix (uint256)
            _repayment,   // _repayment (uint256)
            v,  // v (uint8)
            r,  // r (bytes32)
            s  // s (bytes32)
        );
    }
}


contract TestLongMint is BaseSetup {
    uint256 _margin = 5000000000000000000;  // 5 ETH
    uint32 _nftfId = 8395;
    bool _position = true;  // Long position
    uint256 _leverage = 1000000000000000000;  // x1
    uint256 _premium = 908438124943164160;  // 0.908 ETH
    uint256 _expiryUnix = 1663700471;  // 20 September 2022
    uint256 _repayment = 13090000000000000000;  // 13.09 ETH
    uint256 _response = 140000000000000000001;  // 14 ETH


    function setUp() public virtual override {
        BaseSetup.setUp();
    }

    function testMintLong() public {
        console.log(
            "Mint a long position and activate it."
        );

        bytes32 hash = keccak256(abi.encodePacked(_margin, _nftfId, _position, _leverage, _premium, _expiryUnix, _repayment));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, hash);

        vm.startPrank(user);
        position_contract.mintPosition{ value: _margin }(
            _nftfId,  // _nftfId (uint32)
            _position,  // _position (bool)
            _leverage,  // _leverage (uint256)
            _premium,  // _premium (uint256)
            _expiryUnix,  // _expiryUnix (uint256)
            _repayment,   // _repayment (uint256)
            v,  // v (uint8)
            r,  // r (bytes32)
            s  // s (bytes32)
        );

        assertEq(position_contract.balanceOf(user), 1);
        assertEq(position_contract.ownerOf(1), user);

        vm.warp(_expiryUnix + 1);

        bytes32 requestId = position_contract.triggerPosition(1);
        mockOracle.fulfillOracleRequest(requestId, bytes32(_response));
        // TODO: Continue long cases
    }
}


contract TestTriggerPosition is BaseSetup {
    uint256 _margin = 5000000000000000000;  // 5 ETH
    uint32 _nftfId = 8395;
    bool _position = true;  // Long position
    uint256 _leverage = 1000000000000000000;  // x1
    uint256 _premium = 908438124943164160;  // 0.908 ETH
    uint256 _expiryUnix = 1663700471;  // 20 September 2022
    uint256 _repayment = 13090000000000000000;  // 13.09 ETH
    uint256 _response = 140000000000000000001;  // 14 ETH


    function setUp() public virtual override {
        BaseSetup.setUp();
    }

    function testFailNoPosition() public {
        console.log(
            "Cannot trigger a position as it doesn't exist."
        );

        bytes32 hash = keccak256(abi.encodePacked(_margin, _nftfId, _position, _leverage, _premium, _expiryUnix, _repayment));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, hash);

        vm.startPrank(user);
        position_contract.mintPosition{ value: _margin }(
            _nftfId,  // _nftfId (uint32)
            _position,  // _position (bool)
            _leverage,  // _leverage (uint256)
            _premium,  // _premium (uint256)
            _expiryUnix,  // _expiryUnix (uint256)
            _repayment,   // _repayment (uint256)
            v,  // v (uint8)
            r,  // r (bytes32)
            s  // s (bytes32)
        );

        assertEq(position_contract.balanceOf(user), 1);
        assertEq(position_contract.ownerOf(1), user);

        bytes32 requestId = position_contract.triggerPosition(999);
    }

    function testFailNotExpired() public {
        console.log(
            "Cannot trigger a position as the loan has not expired."
        );

        bytes32 hash = keccak256(abi.encodePacked(_margin, _nftfId, _position, _leverage, _premium, _expiryUnix, _repayment));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, hash);

        vm.startPrank(user);
        position_contract.mintPosition{ value: _margin }(
            _nftfId,  // _nftfId (uint32)
            _position,  // _position (bool)
            _leverage,  // _leverage (uint256)
            _premium,  // _premium (uint256)
            _expiryUnix,  // _expiryUnix (uint256)
            _repayment,   // _repayment (uint256)
            v,  // v (uint8)
            r,  // r (bytes32)
            s  // s (bytes32)
        );

        assertEq(position_contract.balanceOf(user), 1);
        assertEq(position_contract.ownerOf(1), user);

        bytes32 requestId = position_contract.triggerPosition(1);
    }
}


contract TestWithdrawChainlink is BaseSetup {
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
            "Should not withdraw link from the smart contract as sender is not owner."
        );

        vm.prank(user);
        position_contract.withdrawLink();
    }
}

contract TestWithdrawAllocations is BaseSetup {
    function setUp() public virtual override {
        BaseSetup.setUp();
    }

    function testWithdrawAllocation() public {
        console.log(
            "Withdraw allocation from the smart contract as owner."
        );

        vm.prank(gradient);
        position_contract.withdrawAllocation(100 ether);

        assertEq(0, position_contract.allocatedLiquidity(gradient));
    }

    function testFailWithdrawBigAllocation() public {
        console.log(
            "Should not withdraw allocation from the smart contract due to an invalid amount."
        );

        vm.prank(gradient);
        position_contract.withdrawAllocation(10000 ether);
    }

    function testFailWithdrawAllocation() public {
        console.log(
            "Should not withdraw allocation from the smart contract as sender is not owner."
        );

        vm.prank(user);
        position_contract.withdrawAllocation(100 ether);
    }
}
