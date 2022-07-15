// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import "solmate/tokens/ERC721.sol";
import "openzeppelin-contracts/contracts/utils/Strings.sol";
import "openzeppelin-contracts/contracts/access/Ownable.sol";

error NonExistentTokenURI();
error WithdrawTransfer();
error ProtectionNotExpired();
error ProtectionNonExistent();

interface NFTfi {
    function loanRepaidOrLiquidated(uint32) external view returns (bool);
}

/**
 * @title Gradient Insurance (v0.1) contract
 * @author @cairoeth
 * @dev ERC721 contract from which NFTs are minted to represent loan protection.
 **/
contract Insurance is ERC721, Ownable, ERC721TokenReceiver {
    using Strings for uint256;
    string public baseURI = "";
    address payee;
    address nftfiAddress;

    mapping(uint256 => uint256) private stake;

    constructor(address nftfi) ERC721("Gradient Insurance", "INSURANCE") {
        payee = msg.sender;
        nftfiAddress = nftfi;
    }

    /**
    * @dev Mints ERC721 token that represents loan protection
    * @param recipient is the receiver address of the loan
    * @param nftfiId is the id of the NFTfi Promissory Note
    **/
    function mintProtection(address recipient, uint32 nftfiId) public payable onlyOwner {
        /// msg.value value is amount of funds staked to cover the protection in case of default
        stake[newTokenId] = msg.value;
        _safeMint(recipient, nftfiId);
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
    function setNFTfiAddress(address _counter) external onlyOwner {
       nftfiAddress = _counter;
    }

    /**
    * @dev Burns ERC721 token and returns stake when borrower pays back the loan.
    * @param nftfiId is the id of the NFTfi Promissory Note/protection NFT 
    **/
    function borrowerPayed(uint32 nftfiId) external {
        if (NFTfi(nftfiAddress).loanRepaidOrLiquidated(nftfiId)) {
            _burn(nftfiId);
            (bool transferTx, ) = payee.call{value: stake[nftfiId]}("");
            if (!transferTx) {
                revert WithdrawTransfer();
            }
            stake[nftfiId] = 0;
        }
        revert ProtectionNotExpired();
    }

    /**
    * @dev Executed when the borrower defaults and collateral is transfered here to liquidate and cover any possible losses.
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

    /**
    * @dev Covers protection and losses after collateral is liquidated.
    * @param liquidation is the $ earned from the collateral dutch auction
    * @param nftfiId is the id of the NFTfi Promissory Note/protection NFT
    **/
    function coverLosses(uint64 liquidation, uint32 nftfiId) external {
        uint32 upperBound = 200;
        uint32 lowerBound = 100;
        address receiver = _ownerOf[nftfiId];
        /// Check if nftfiId is burned or not
        if (receiver == address(0)) {
            revert ProtectionNonExistent();
        }

        /// Option A
        if (liquidation > upperBound) {
            _burn(nftfiId);
            /// Return all $ from the liquidation to protection owner
            (bool transferTx, ) = receiver.call{value: liquidation}("");
            if (!transferTx) {
                revert WithdrawTransfer();
            }
            /// Return stake
            (bool transferTx, ) = payee.call{value: stake[nftfiId]}("");
            if (!transferTx) {
                revert WithdrawTransfer();
            }
            stake[nftfiId] = 0;
        }
        /// Option B
        else if (lowerBound < liquidation < upperBound) {
            _burn(nftfiId);
            uint32 losses = upperBound - liquidation;
            stake[nftfiId] - losses;
            /// Return all $ from the liquidation to protection owner and cover lossses
            (bool transferTx, ) = receiver.call{value: liquidation + losses}("");
            if (!transferTx) {
                revert WithdrawTransfer();
            }
            /// Return remaining stake, if any.
            (bool transferTx, ) = payee.call{value: stake[nftfiId]}("");
            if (!transferTx) {
                revert WithdrawTransfer();
            }
        }
        /// Option C
        else if (liquidation < lowerBound) {
            _burn(nftfiId);
            /// Return all $ from the liquidation and protection to protection owner
            (bool transferTx, ) = receiver.call{value: liquidation + stake[nftfiId]}("");
            if (!transferTx) {
                revert WithdrawTransfer();
            }
            stake[nftfiId] = 0;
        }
    }
}
