// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import "solmate/tokens/ERC721.sol";
import "solmate/utils/ReentrancyGuard.sol";
import "openzeppelin-contracts/contracts/utils/Strings.sol";
import "openzeppelin-contracts/contracts/access/Ownable.sol";

error NonExistentTokenURI();
error WithdrawTransfer();
error ProtectionNotExpired();
error CollateralNotLiquidated();

interface NFTfi {
    function loanRepaidOrLiquidated(uint32) external view returns (bool);
}

/**
 * @title Gradient Protection (v0.1) contract
 * @author @cairoeth
 * @dev ERC721 contract from which NFTs are minted to represent loan protection.
 **/
contract Protection is ERC721, Ownable, ReentrancyGuard, ERC721TokenReceiver {
    using Strings for uint256;
    string public baseURI = "";
    address payee;
    address nftfiAddress;

    mapping(uint32 => uint256) private stake;
    mapping(uint32 => uint32) private lowerBound;
    mapping(uint32 => uint32) private upperBound;
    mapping(uint32 => uint256) private liquidation;
    mapping(uint32 => bool) private liquidationStatus;

    constructor(address nftfi) ERC721("Gradient Protection", "PROTECTION") {
        payee = msg.sender;
        nftfiAddress = nftfi;
    }

    /**
    * @dev Mints ERC721 token that represents loan protection
    * @param recipient is the receiver address of the protection (lender)
    * @param nftfiId is the id of the NFTfi Promissory Note
    **/
    function _mintProtection(address recipient, uint32 nftfiId, uint32 lowerBoundvalue, uint32 upperBoundvalue) public payable onlyOwner {
        /// msg.value value is amount of funds staked to cover the protection in case of default
        _safeMint(recipient, nftfiId);
        stake[nftfiId] = msg.value;
        lowerBound[nftfiId] = lowerBoundvalue;
        upperBound[nftfiId] = upperBoundvalue;
    }

    /**
    * @dev Returns the URL of a token's metadata
    * @param tokenId is the token id
    **/
    function tokenURI(uint256 tokenId)
        public
        view
        virtual
        override
        returns (string memory)
    {
        if (ownerOf(tokenId) == address(0)) {
            revert NonExistentTokenURI();
        }
        return
            bytes(baseURI).length > 0
                ? string(abi.encodePacked(baseURI, tokenId.toString()))
                : "";
    }

    /**
    * @dev Sets the NFTfi address
    * @param _counter is the NFTfi main smart contract address
    **/
    function _setNFTfiAddress(address _counter) external onlyOwner {
       nftfiAddress = _counter;
    }

    /**
    * @notice Activates the protection after loan reaches maturity
    * @param nftfiId is the id of the NFTfi Promissory Note/protection NFT 
    **/
    function _activateProtection(uint32 nftfiId) external nonReentrant {
        /// Require NFT protection not to be burned
        require(_ownerOf[nftfiId] != address(0), "Protection does not exist");

        /// Closes a expired protection when the borrower payed back or when the lender wants to keep the collateral
        if (NFTfi(nftfiAddress).loanRepaidOrLiquidated(nftfiId) && liquidation[nftfiId] == 0 && !liquidationStatus[nftfiId]) {
            _burn(nftfiId);
            (bool transferTx, ) = payee.call{value: stake[nftfiId]}("");
            if (!transferTx) {
                revert WithdrawTransfer();
            }
            stake[nftfiId] = 0;
        }
        /// Closes a protection after the collateral has been liquidated by covering any losses
        else if  (NFTfi(nftfiAddress).loanRepaidOrLiquidated(nftfiId) && liquidation[nftfiId] > 0 && liquidationStatus[nftfiId]) {
            /// Option A: The collateral is liquidated at a price above the upper-bound of the protection 
            if (liquidation[nftfiId] > upperBound[nftfiId]) {
                _burn(nftfiId);
                /// Return all $ from the liquidation to protection owner
                (bool transferTx1, ) = _ownerOf[nftfiId].call{value: liquidation[nftfiId]}("");
                if (!transferTx1) {
                    revert WithdrawTransfer();
                }
                /// Return stake
                (bool transferTx2, ) = payee.call{value: stake[nftfiId]}("");
                if (!transferTx2) {
                    revert WithdrawTransfer();
                }
                stake[nftfiId] = 0;
            }
            /// Option B: The collateral is liquidated at a price between the bounds of the protection
            else if (lowerBound[nftfiId] < liquidation[nftfiId] && liquidation[nftfiId] < upperBound[nftfiId]) {
                _burn(nftfiId);
                uint256 losses = upperBound[nftfiId] - liquidation[nftfiId];
                stake[nftfiId] - losses;
                /// Return all $ from the liquidation to protection owner and cover lossses
                (bool transferTx1, ) = _ownerOf[nftfiId].call{value: liquidation[nftfiId] + losses}("");
                if (!transferTx1) {
                    revert WithdrawTransfer();
                }
                /// Return remaining stake, if any.
                (bool transferTx2, ) = payee.call{value: stake[nftfiId]}("");
                if (!transferTx2) {
                    revert WithdrawTransfer();
                }
            }
            /// Option C: The collateral is liquidated at a price below the lower-bound of the protection
            else if (liquidation[nftfiId] < lowerBound[nftfiId]) {
                _burn(nftfiId);
                /// Return all $ from the liquidation and protection to protection owner
                (bool transferTx, ) = _ownerOf[nftfiId].call{value: liquidation[nftfiId] + stake[nftfiId]}("");
                if (!transferTx) {
                    revert WithdrawTransfer();
                }
                stake[nftfiId] = 0;
            }
            /// Collateral liquidation is activate and but not sold yet
            else if (NFTfi(nftfiAddress).loanRepaidOrLiquidated(nftfiId) && liquidationStatus[nftfiId]) {
                revert CollateralNotLiquidated();
            }
        }
        else {
            revert ProtectionNotExpired();
        }
    }

    /**
    * @dev Liquidation executed by the lender when the borrower defaults and the lender wants to cover any losses.
    **/
    function onERC721Received(
        address,
        address,
        uint256,
        bytes calldata
    ) external override virtual returns (bytes4) {
        /// liquidate nft with a dutch auction through seaport
        return ERC721TokenReceiver.onERC721Received.selector;
    }
}
