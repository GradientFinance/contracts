// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import "solmate/tokens/ERC721.sol";
import "openzeppelin-contracts/contracts/utils/Strings.sol";
import "openzeppelin-contracts/contracts/access/Ownable.sol";

error NonExistentTokenURI();
error WithdrawTransfer();
error ProtectionNotExpired();

interface NFTfi {
    function loanRepaidOrLiquidated(uint32) external view returns (bool);
}

/**
 * @title Gradient Insurance (v0.1) contract
 * @author Gradient (cairoeth, ...)
 * @dev ERC721 contract from which NFTs are minted to represent loan protection.
 **/
contract Insurance is ERC721, Ownable, ERC721TokenReceiver {
    using Strings for uint256;
    string public baseURI = "";
    uint256 public currentTokenId;
    address payee;
    address nftfiAddress;

    mapping(uint256 => uint256) private stake;
    mapping(uint256 => uint32) private connection;

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
        uint256 newTokenId = ++currentTokenId;

        /// msg.value value is amount of funds staked to cover the protection in case of default
        stake[newTokenId] = msg.value;
        connection[newTokenId] = nftfiId;
        _safeMint(recipient, newTokenId);
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
    * @param NFTfiId is the id of the NFTfi Promissory Note
    **/
    function borrowerPayed(uint32 NFTfiId) external {
        if (NFTfi(nftfiAddress).loanRepaidOrLiquidated(NFTfiId)) {
            uint256 TokenId = connection[NFTfiId];
            (bool transferTx, ) = payee.call{value: stake[TokenId]}("");
            if (!transferTx) {
                revert WithdrawTransfer();
            }
            _burn(TokenId);
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
        return ERC721TokenReceiver.onERC721Received.selector;
    }
}
