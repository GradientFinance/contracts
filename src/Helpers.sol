// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

/**
 * @title Gradient (v0.2) helpers
 * @author cairoeth
 * @dev Contract which contains helper functions for main contract.
 **/
contract Helpers {
        /**
        * @dev Returns an address as a string memory
        * @param _address is address to transform
        **/
        function _toAsciiString(address _address) internal pure returns (string memory) {
            bytes memory s = new bytes(40);
            for (uint i = 0; i < 20; i++) {
                bytes1 b = bytes1(uint8(uint(uint160(_address)) / (2**(8*(19 - i)))));
                bytes1 hi = bytes1(uint8(b) / 16);
                bytes1 lo = bytes1(uint8(b) - 16 * uint8(hi));
                s[2*i] = _char(hi);
                s[2*i+1] = _char(lo);            
            }
            return string(s);
        }

        /**
        * @dev Allows to manipulate bytes for toAsciiString function
        * @param b is a byte
        **/
        function _char(bytes1 b) internal pure returns (bytes1 c) {
            if (uint8(b) < 10) return bytes1(uint8(b) + 0x30);
            else return bytes1(uint8(b) + 0x57);
        }

        /**
        * @notice Implementation of ecrecover to verify signature
        * @param message Hashed mint parameters
        * @param _signature Address deployer signature of parameters
        **/
        function recoverSigner(bytes32 message, bytes memory _signature)
            public
            pure
            returns (address)
        {
            uint8 v;
            bytes32 r;
            bytes32 s;
            (v, r, s) = splitSignature(_signature);
            return ecrecover(message, v, r, s);
        }

        /**
        * @notice Separates a tx signature into v, r, and s values
        * @param _signature Address deployer signature of parameters  
        **/
        function splitSignature(bytes memory _signature)
            public
            pure
            returns (uint8, bytes32, bytes32)
        {
            require(_signature.length == 65);
            bytes32 r;
            bytes32 s;
            uint8 v;
            assembly {
                // First 32 bytes, after the length prefix
                r := mload(add(_signature, 32))
                // Second 32 bytes
                s := mload(add(_signature, 64))
                // Final byte (first byte of the next 32 bytes)
                v := byte(0, mload(add(_signature, 96)))
            }

            return (v, r, s);
        }
}
