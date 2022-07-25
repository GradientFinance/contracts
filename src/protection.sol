// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import "solmate/tokens/ERC721.sol";
import "solmate/utils/ReentrancyGuard.sol";
import "openzeppelin-contracts/contracts/utils/Strings.sol";
import "openzeppelin-contracts/contracts/access/Ownable.sol";
import 'chainlink/contracts/src/v0.8/ChainlinkClient.sol';
import './Helpers.sol';

error NonExistentTokenURI();
error WithdrawTransfer();
error ProtectionStillActive();
error LiquidationNotFound();

interface IDirectLoanBase {
    function loanRepaidOrLiquidated(uint32) external view returns (bool);
}

/**
 * @title Gradient Protection (v0.1) contract
 * @author @cairoeth
 * @dev ERC721 contract from which NFTs are minted to represent loan protection.
 **/
contract Protection is ERC721, Ownable, ReentrancyGuard, Helpers, ChainlinkClient {
    using Strings for uint256;
    using Chainlink for Chainlink.Request;
    bytes32 private jobId;
    uint256 private fee;
    address private nftfiAddress;
    string public baseURI;

    mapping(uint32 => uint256) private expiry;
    mapping(uint32 => uint256) private lowerBound;
    mapping(uint32 => uint256) private upperBound;
    mapping(uint32 => address) private collateralContractToProtection;
    mapping(uint32 => uint256) private collateralIdToProtection;
    mapping(uint32 => uint256) private startingUnix;
    mapping(bytes32 => uint32) private requestToProtection;
    mapping(uint32 => uint256) public stake;

    event RequestedPrice(bytes32 indexed requestId, uint256 price);

    /**
    * @notice Rinkeby parameters:
    * @param _ChainlinkToken 0x01BE23585060835E02B77ef475b0Cc51aA1e0709
    * @param _ChainlinkOracle 0xf3FBB7f3391F62C8fe53f89B41dFC8159EE9653f
    * @param _jobId ca98366cc7314957b8c012c72f05aeeb
    * @param _fee (1 * LINK_DIVISIBILITY) / 10 /// 0,1 * 10**18 (Varies by network and job)
    **/
    constructor(address _ChainlinkToken, address _ChainlinkOracle, bytes32 _jobId, uint256 _fee, string memory _URI, address _addressNFTfi) ERC721("Gradient Protection", "PROTECTION") {
        setChainlinkToken(_ChainlinkToken);
        setChainlinkOracle(_ChainlinkOracle);
        jobId = _jobId;
        fee = _fee;
        baseURI = _URI;
        nftfiAddress = _addressNFTfi;
    }

    /**
    * @notice Mints ERC721 token that represents loan protection
    * @param _recipient Receiver address of the protection (lender)
    * @param _nftfiId ID of the NFTfi Promissory Note
    * @param _lowerBoundVal Lower boundary of the protection
    * @param _upperBoundVal Upper boundary of the protection
    * @param _unixStart Unix timestamp when loan starts (NFTfi)
    * @param _unixExpiry Unix timmestamp when loan expires (NFTfi)    
    * @param _collateralContract Contract address of loan collateral
    * @param _collateralId Token ID of loan collateral    
    **/
    function mintProtection(address _recipient, uint32 _nftfiId, uint256 _lowerBoundVal, uint256 _upperBoundVal, uint256 _unixStart, uint256 _unixExpiry, address _collateralContract, uint256 _collateralId) public payable onlyOwner {
        /// msg.value value: amount of funds (wei) staked to cover losses of any collateral liquidation in case the borrower defaults
        _safeMint(_recipient, _nftfiId);
        stake[_nftfiId] = msg.value;
        lowerBound[_nftfiId] = _lowerBoundVal;
        upperBound[_nftfiId] = _upperBoundVal;
        startingUnix[_nftfiId] = _unixStart;
        expiry[_nftfiId] = _unixExpiry + 1 days;
        collateralContractToProtection[_nftfiId] = _collateralContract;
        collateralIdToProtection[_nftfiId] = _collateralId;
    }

    /**
    * @notice Returns the URL of a token's metadata
    * @param tokenId Token ID
    **/
    function tokenURI(uint256 tokenId)
        public
        view
        virtual
        override
        returns (string memory)
    {
        require(_ownerOf[tokenId] != address(0), "Non-existent token URI");
        return
            bytes(baseURI).length > 0
                ? string(abi.encodePacked(baseURI, tokenId.toString()))
                : "";
    }

    /**
    * @notice Triggers the protection after loan reaches maturity
    * @param _nftfiId is the id of the NFTfi Promissory Note/protection NFT 
    **/
    function triggerProtection(uint32 _nftfiId) external nonReentrant {
        require(_ownerOf[_nftfiId] != address(0), "Protection does not exist");
        require(IDirectLoanBase(nftfiAddress).loanRepaidOrLiquidated(_nftfiId));

        /// Closes a expired protection when the borrower payed back or when the lender wants to keep the collateral
        if (block.timestamp > expiry[_nftfiId]) {
            uint256 payback = stake[_nftfiId];
            stake[_nftfiId] = 0;
            _burn(_nftfiId);

            /// Return stake
            (bool transferTx, ) = owner().call{value: payback}("");
            require(transferTx, "Payback transfer failed.");
        }
        else {
            requestPrice(collateralContractToProtection[_nftfiId], collateralIdToProtection[_nftfiId], startingUnix[_nftfiId], _nftfiId);
        }
    }

    /**
    * @dev Creates a Chainlink request to retrieve API response to validate collateral liquidation on OpenSea
    * @param _contractAddress Contract address of loan collateral
    * @param _tokenId Token ID of loan collateral
    * @param _startingUnix Unix timestamp when loan starts (NFTfi)
    * @param _nftfiId Token ID of ERC721 protection 
    **/
    function requestPrice(address _contractAddress, uint256 _tokenId, uint256 _startingUnix, uint32 _nftfiId) private {
        Chainlink.Request memory req = buildChainlinkRequest(jobId, address(this), this.fulfill.selector);

        /// Set the URL to perform the GET request on -- will change!
        string memory s = string.concat('http://disestevez.pythonanywhere.com/', _toAsciiString(_contractAddress));
        s = string.concat(s, "/");
        s = string.concat(s, Strings.toString(_tokenId));
        s = string.concat(s, "/");
        s = string.concat(s, Strings.toString(_startingUnix));
        req.add('get', s);

        req.add('path', 'price'); /// Chainlink nodes 1.0.0 and later support this format

        /// Multiply 1
        int256 timesAmount = 1;
        req.addInt('times', timesAmount);

        /// Sends the request
        bytes32 sendRequest = sendChainlinkRequest(req, fee);
        requestToProtection[sendRequest] = _nftfiId;
    }

    /**
    * @notice Runs the protection using the data from OpenSea
    * @param _nftfiId is the id of the NFTfi Promissory Note/protection NFT 
    **/
    function activateProtection(uint32 _nftfiId, uint256 _liquidationFunds) private {
         /// Check to prevent oracle manipulation by external calls 
        require(_ownerOf[_nftfiId] != address(0), "Protection does not exist");

        /// Closes a protection after the collateral has been liquidated by covering any losses
        if (_liquidationFunds < 2**256 - 7) {
            /// Option A: The collateral is liquidated at a price above the upper-bound of the protection 
            if (_liquidationFunds > upperBound[_nftfiId]) {
                uint256 payback = stake[_nftfiId];
                stake[_nftfiId] = 0;
                _burn(_nftfiId);

                /// Return stake
                (bool transferTx, ) = owner().call{value: payback}("");
                require(transferTx, "Payback transfer failed.");
            }
            /// Option B: The collateral is liquidated at a price between the bounds of the protection
            else if (lowerBound[_nftfiId] < _liquidationFunds && _liquidationFunds < upperBound[_nftfiId]) {
                address receiverProtection = _ownerOf[_nftfiId];
                uint256 losses = upperBound[_nftfiId] - _liquidationFunds;
                uint256 payback = stake[_nftfiId] - losses;
                stake[_nftfiId] = 0;
                _burn(_nftfiId);

                /// Return remaining stake, if any.
                (bool transferTx1, ) = owner().call{value: payback}("");
                require(transferTx1, "Payback transfer failed.");

                /// Return all $ from the liquidation to protection owner and cover lossses
                (bool transferTx2, ) = receiverProtection.call{value: losses}("");
                require(transferTx2, "Protection transfer failed.");
            }
            /// Option C: The collateral is liquidated at a price below the lower-bound of the protection
            else if (_liquidationFunds < lowerBound[_nftfiId]) {
                address receiverProtection = _ownerOf[_nftfiId];
                uint256 payback = stake[_nftfiId];
                stake[_nftfiId] = 0;
                _burn(_nftfiId);

                /// Return all $ from the liquidation and protection to protection owner
                (bool transferTx, ) = receiverProtection.call{value: payback}("");
                require(transferTx, "Protection transfer failed.");
            }
        }
        else {
            revert LiquidationNotFound();
        }
    }

    /**
    * @dev Recieves oracle response in the form of uint256
    * @param _requestId Chainlink request ID
    * @param _price fetched price (wei)
    **/
    function fulfill(bytes32 _requestId, uint256 _price) public recordChainlinkFulfillment(_requestId) {
        emit RequestedPrice(_requestId, _price);
        activateProtection(requestToProtection[_requestId], _price);
    }

    /**
    * @notice Sets the NFTfi address
    * @param _address is the NFTfi main smart contract address
    **/
    function setNFTfiAddress(address _address) external onlyOwner {
       nftfiAddress = _address;
    }

    /**
    * @notice Allows to withdraw LINK tokens
    **/
    function withdrawLink() public onlyOwner {
        LinkTokenInterface link = LinkTokenInterface(chainlinkTokenAddress());
        require(link.transfer(owner(), link.balanceOf(address(this))), 'Unable to transfer');
    }
}
