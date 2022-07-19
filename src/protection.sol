// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import "solmate/tokens/ERC721.sol";
import "solmate/utils/ReentrancyGuard.sol";
import "openzeppelin-contracts/contracts/utils/Strings.sol";
import "openzeppelin-contracts/contracts/access/Ownable.sol";
import 'chainlink/contracts/src/v0.8/ChainlinkClient.sol';
import './helpers.sol';


error NonExistentTokenURI();
error WithdrawTransfer();
error ProtectionStillActive();

interface IDirectLoanBase {
    function loanRepaidOrLiquidated(uint32) external view returns (bool);
}

/**
 * @title Gradient Protection (v0.1) contract
 * @author @cairoeth
 * @dev ERC721 contract from which NFTs are minted to represent loan protection.
 **/
contract Protection is ERC721, Ownable, ReentrancyGuard, ERC721TokenReceiver, Helpers, ChainlinkClient {
    using Strings for uint256;
    using Chainlink for Chainlink.Request;
    string public baseURI = "";
    address payee;
    address nftfiAddress;
    bytes32 private jobId;
    uint256 private fee;

    mapping(uint32 => uint256) public stake;
    mapping(uint32 => uint256) private expiry;
    mapping(uint32 => uint256) private lowerBound;
    mapping(uint32 => uint256) private upperBound;
    mapping(uint32 => address) private collateralContractToProtection;
    mapping(uint32 => uint256) private collateralIdToProtection;
    mapping(uint32 => uint256) private startingUnix;
    mapping(bytes32 => uint32) internal requestToProtection;

    event RequestPrice(bytes32 indexed requestId, uint256 price);

    constructor() ERC721("Gradient Protection", "PROTECTION") {
        payee = msg.sender;
        setChainlinkToken(0x01BE23585060835E02B77ef475b0Cc51aA1e0709);
        setChainlinkOracle(0xf3FBB7f3391F62C8fe53f89B41dFC8159EE9653f);
        jobId = 'ca98366cc7314957b8c012c72f05aeeb';
        fee = (1 * LINK_DIVISIBILITY) / 10; // 0,1 * 10**18 (Varies by network and job)
    }

    /**
    * @dev Mints ERC721 token that represents loan protection
    * @param recipient is the receiver address of the protection (lender)
    * @param nftfiId is the id of the NFTfi Promissory Note
    **/
    function _mintProtection(address recipient, uint32 nftfiId, uint256 lowerBoundvalue, uint256 upperBoundvalue, uint256 startingUnixTime, uint256 expiryUnix, address collateralContract, uint256 collateralId) public payable onlyOwner {
        /// msg.value value is amount of funds staked to cover the protection in case of default
        _safeMint(recipient, nftfiId);
        stake[nftfiId] = msg.value;
        lowerBound[nftfiId] = lowerBoundvalue;
        upperBound[nftfiId] = upperBoundvalue;
        expiry[nftfiId] = expiryUnix + 1 days;
        startingUnix[nftfiId] = startingUnixTime;
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
     * Create a Chainlink request to retrieve API response, find the target
     * data, then multiply by 1000000000000000000 (to remove decimal places from data).
     */
    function _RequestPrice(address contractAddress, uint256 tokenId, uint256 _startingUnix, uint32 protectionId) public {
        Chainlink.Request memory req = buildChainlinkRequest(jobId, address(this), this.fulfill.selector);

        // Set the URL to perform the GET request on
        string memory s = string.concat('http://disestevez.pythonanywhere.com/', _toAsciiString(contractAddress));
        s = string.concat(s, "/");
        s = string.concat(s, Strings.toString(tokenId));
        s = string.concat(s, "/");
        s = string.concat(s, Strings.toString(_startingUnix));
        req.add('get', s);

        req.add('path', 'price'); // Chainlink nodes 1.0.0 and later support this format

        // Multiply 1
        int256 timesAmount = 1;
        req.addInt('times', timesAmount);

        // Sends the request
        bytes32 sendRequest = sendChainlinkRequest(req, fee);
        requestToProtection[sendRequest] = protectionId;
    }

    /**
    * @notice Triggers the protection after loan reaches maturity
    * @param nftfiId is the id of the NFTfi Promissory Note/protection NFT 
    **/
    function _triggerProtection(uint32 nftfiId) external nonReentrant {
        /// Require NFT protection not to be burned
        require(_ownerOf[nftfiId] != address(0), "Protection does not exist");

        /// Closes a expired protection when the borrower payed back or when the lender wants to keep the collateral
        if (IDirectLoanBase(nftfiAddress).loanRepaidOrLiquidated(nftfiId)) {
            _RequestPrice(collateralContractToProtection[nftfiId], collateralIdToProtection[nftfiId], startingUnix[nftfiId], nftfiId);
        }
        else {
            revert ProtectionStillActive();
        }
    }

    /**
    * @notice Runs the protection using the data from OpenSea
    * @param nftfiId is the id of the NFTfi Promissory Note/protection NFT 
    **/
    function _activateProtection(uint32 nftfiId, uint256 liquidationFunds) internal {
         /// Check to prevent any external calls
        require(_ownerOf[nftfiId] != address(0), "Protection does not exist");

        if (liquidationFunds > 12000000000000000000000 && block.timestamp > expiry[nftfiId]) {
            _burn(nftfiId);
            (bool transferTx, ) = payee.call{value: stake[nftfiId]}("");
            if (!transferTx) {
                revert WithdrawTransfer();
            }
            stake[nftfiId] = 0;
        }
        /// Closes a protection after the collateral has been liquidated by covering any losses
        else if (0 < liquidationFunds && liquidationFunds < 12000000000000000000000) {
            /// Option A: The collateral is liquidated at a price above the upper-bound of the protection 
            if (liquidationFunds > upperBound[nftfiId]) {
                _burn(nftfiId);
                /// Return stake
                (bool transferTx2, ) = payee.call{value: stake[nftfiId]}("");
                if (!transferTx2) {
                    revert WithdrawTransfer();
                }
                stake[nftfiId] = 0;
            }
            /// Option B: The collateral is liquidated at a price between the bounds of the protection
            else if (lowerBound[nftfiId] < liquidationFunds && liquidationFunds < upperBound[nftfiId]) {
                address payable receiverProtection = _ownerOf[nftfiId];
                uint256 losses = upperBound[nftfiId] - liquidationFunds;
                uint256 payback = stake[nftfiId] - losses;
                _burn(nftfiId);
                stake[nftfiId] = 0;
                /// Return all $ from the liquidation to protection owner and cover lossses
                (bool transferTx1, ) = receiverProtection.call{value: losses}("");
                if (!transferTx1) {
                    revert WithdrawTransfer();
                }
                /// Return remaining stake, if any.
                (bool transferTx2, ) = payee.call{value: payback}("");
                if (!transferTx2) {
                    revert WithdrawTransfer();
                }
            }
            /// Option C: The collateral is liquidated at a price below the lower-bound of the protection
            else if (liquidationFunds < lowerBound[nftfiId]) {
                address payable receiverProtection = _ownerOf[nftfiId];
                _burn(nftfiId);
                /// Return all $ from the liquidation and protection to protection owner
                (bool transferTx, ) = receiverProtection.call{value: stake[nftfiId]}("");
                if (!transferTx) {
                    revert WithdrawTransfer();
                }
                stake[nftfiId] = 0;
            }
        }
    }

    /**
     * Receive the response in the form of uint256
     */
    function fulfill(bytes32 _requestId, uint256 _price) public recordChainlinkFulfillment(_requestId) {
        emit RequestPrice(_requestId, _price);
        _activateProtection(requestToProtection[_requestId], _price);
    }

    /**
     * Allow withdraw of Link tokens from the contract
     */
    function withdrawLink() public onlyOwner {
        LinkTokenInterface link = LinkTokenInterface(chainlinkTokenAddress());
        require(link.transfer(msg.sender, link.balanceOf(address(this))), 'Unable to transfer');
    }

}
