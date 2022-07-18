// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import "solmate/tokens/ERC721.sol";
import "solmate/utils/ReentrancyGuard.sol";
import "openzeppelin-contracts/contracts/utils/Strings.sol";
import "openzeppelin-contracts/contracts/access/Ownable.sol";
import "./APIConsumer.sol";

error NonExistentTokenURI();
error WithdrawTransfer();
error ProtectionNotExpired();

interface NFTfi {
    function loanRepaidOrLiquidated(uint32) external view returns (bool);
    function loanIdToLoan(uint32) external returns (
        uint256 loanPrincipalAmount,
        uint256 maximumRepaymentAmount,
        uint256 nftCollateralId,
        address loanERC20Denomination,
        uint32 loanDuration,
        uint16 loanInterestRateForDurationInBasisPoints,
        uint16 loanAdminFeeInBasisPoints,
        address nftCollateralWrapper,
        uint64 loanStartTime,
        address nftCollateralContract,
        address borrower
    );
}

/**
 * @title Gradient Protection (v0.1) contract
 * @author @cairoeth
 * @dev ERC721 contract from which NFTs are minted to represent loan protection.
 **/
contract Protection is ERC721, Ownable, ReentrancyGuard, ERC721TokenReceiver, APIConsumer {
    using Strings for uint256;
    string public baseURI = "";
    address payee;
    address nftfiAddress;

    NFTfi NFTfiContract = NFTfi(nftfiAddress);

    mapping(uint32 => uint256) public stake;
    mapping(uint32 => uint256) private expiry;
    mapping(uint32 => uint256) private lowerBound;
    mapping(uint32 => uint256) private upperBound;
    mapping(uint32 => address) private collateralContractToProtection;
    mapping(uint32 => uint256) private collateralIdToProtection;

    constructor() ERC721("Gradient Protection", "PROTECTION") {
        payee = msg.sender;
    }

    /**
    * @dev Mints ERC721 token that represents loan protection
    * @param recipient is the receiver address of the protection (lender)
    * @param nftfiId is the id of the NFTfi Promissory Note
    **/
    function _mintProtection(address recipient, uint32 nftfiId, uint256 lowerBoundvalue, uint256 upperBoundvalue, uint256 expiryUnix, address collateralContract, uint256 collateralId) public payable onlyOwner {
        /// msg.value value is amount of funds staked to cover the protection in case of default
        _safeMint(recipient, nftfiId);
        stake[nftfiId] = msg.value;
        lowerBound[nftfiId] = lowerBoundvalue;
        upperBound[nftfiId] = upperBoundvalue;
        expiry[nftfiId] = expiryUnix + 1 days;
        collateralContractToProtection[nftfiId] = collateralContract;
        collateralIdToProtection[nftfiId] = collateralId;
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
    * @param _address is the NFTfi main smart contract address
    **/
    function _setNFTfiAddress(address _address) external onlyOwner {
       nftfiAddress = _address;
    }

    /**
    * @dev Makes the call to the chainlink oracle. its a different function bc it may take some seconds for the value to become updated
    **/
    function _fetchLiquidationValue(uint32 nftfiId) internal {
        _RequestPrice(collateralContractToProtection[nftfiId], collateralIdToProtection[nftfiId]);
    }

    /**
    * @dev Fetches the liquidation value of a loan protection collatereal
    **/
    function _liquidationValue(uint32 nftfiId) internal view returns (uint256) {
        return price[collateralContractToProtection[nftfiId]][collateralIdToProtection[nftfiId]];
    }

    /**
    * @notice Triggers the protection after loan reaches maturity
    * @param nftfiId is the id of the NFTfi Promissory Note/protection NFT 
    **/
    function _triggerProtection(uint32 nftfiId) external nonReentrant {
        /// Require NFT protection not to be burned
        require(_ownerOf[nftfiId] != address(0), "Protection does not exist");
        _fetchLiquidationValue(nftfiId);
        uint256 liquidationFunds = _liquidationValue(nftfiId);

        /// Closes a expired protection when the borrower payed back or when the lender wants to keep the collateral
        if (NFTfiContract.loanRepaidOrLiquidated(nftfiId) && liquidationFunds == 0 && block.timestamp > expiry[nftfiId]) {
            _burn(nftfiId);
            (bool transferTx, ) = payee.call{value: stake[nftfiId]}("");
            if (!transferTx) {
                revert WithdrawTransfer();
            }
            stake[nftfiId] = 0;
        }
        /// Closes a protection after the collateral has been liquidated by covering any losses
        else if  (NFTfiContract.loanRepaidOrLiquidated(nftfiId) && liquidationFunds > 0) {
            /// Option A: The collateral is liquidated at a price above the upper-bound of the protection 
            if (liquidationFunds > upperBound[nftfiId]) {
                _burn(nftfiId);
                /// Return all $ from the liquidation to protection owner
                (bool transferTx1, ) = _ownerOf[nftfiId].call{value: liquidationFunds}("");
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
            else if (lowerBound[nftfiId] < liquidationFunds && liquidationFunds < upperBound[nftfiId]) {
                _burn(nftfiId);
                uint256 losses = upperBound[nftfiId] - liquidationFunds;
                stake[nftfiId] - losses;
                /// Return all $ from the liquidation to protection owner and cover lossses
                (bool transferTx1, ) = _ownerOf[nftfiId].call{value: liquidationFunds + losses}("");
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
            else if (liquidationFunds < lowerBound[nftfiId]) {
                _burn(nftfiId);
                /// Return all $ from the liquidation and protection to protection owner
                (bool transferTx, ) = _ownerOf[nftfiId].call{value: liquidationFunds + stake[nftfiId]}("");
                if (!transferTx) {
                    revert WithdrawTransfer();
                }
                stake[nftfiId] = 0;
            }
        }
        else {
            revert ProtectionNotExpired();
        }
    }
}
