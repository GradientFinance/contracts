// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import "solmate/tokens/ERC721.sol";
import "openzeppelin-contracts/contracts/utils/Strings.sol";
import "openzeppelin-contracts/contracts/access/Ownable.sol";

error NonExistentTokenURI();
error WithdrawTransfer();

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

    mapping(uint256 => uint256) private stake;

    constructor() ERC721("Gradient Insurance", "INSURANCE") {
        payee = msg.sender;
    }

    /**
    * @dev Mints ERC721 token that represents loan protection
    * @param recipient is the receiver address of the loan
    **/
    function mintProtection(address recipient) public payable onlyOwner {
        uint256 newTokenId = ++currentTokenId;

        /// msg.value value is amount of funds staked to cover the protection in case of default
        stake[newTokenId] = msg.value;
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
    * @dev Burns ERC721 token and returns stake when borrower pays back the loan.
    * @param tokenId is the token id 
    **/
    function borrowerPay(uint256 tokenId) external onlyOwner {
        (bool transferTx, ) = payee.call{value: stake[tokenId]}("");
        if (!transferTx) {
            revert WithdrawTransfer();
        }
        _burn(tokenId);
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
