// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import "solmate/tokens/ERC721.sol";
import "solmate/utils/ReentrancyGuard.sol";
import "openzeppelin-contracts/contracts/utils/Strings.sol";
import "openzeppelin-contracts/contracts/access/Ownable.sol";
import 'chainlink/contracts/src/v0.8/ChainlinkClient.sol';
import './Helpers.sol';

/**
 * @title Gradient (v0.2) contract
 * @author cairoeth
 * @dev ERC721 contract from which NFTs are minted to represent a short or long position.
 **/
contract Position is ERC721, Ownable, ReentrancyGuard, Helpers, ChainlinkClient {
    using Strings for uint32;
    using Strings for uint256;
    using Chainlink for Chainlink.Request;
    bytes32 private jobId;
    uint256 private fee;
    uint256 private positionIdCounter = 0;
    string public constant baseURI = "https://app.gradient.city/metadata/";

    struct LoanPosition {
        bool position;
        uint256 margin;
        uint256 leverage;
        uint256 premium;
        uint256 expiryUnix;
        uint256 principal;
        uint32 nftfiId;
    }

    mapping(bytes32 => uint256) private requestToPosition;
    mapping(uint256 => LoanPosition) public positionData;

    event RequestedPrice(bytes32 indexed _requestId, uint256 _value);

    constructor(address _linkAddress, address _oracleAddress) ERC721("Gradient Position", "POSITION") {
        setChainlinkToken(_linkAddress);
        setChainlinkOracle(_oracleAddress);
        jobId = 'ca98366cc7314957b8c012c72f05aeeb';
        fee = (1 * LINK_DIVISIBILITY) / 10; // 0,1 * 10**18 (Varies by network and job)
    }

    /**
    * @notice Mints ERC721 token that represents a long or short position,
    * @param _nftfiId ID of the NFTfi Promissory Note,
    * @param _position True if long or false if short,
    * @param _leverage Increases the risk of getting wiped out but also the potential profits,
    * @param _premium Premium return,
    * @param _expiryUnix Unix timmestamp when NFTfi loan expires,
    * @param _principal Principal of the NFTfi loan,
    * @param _v v part of signature,
    * @param _r r part of signature,
    * @param _s s part of signature.
    **/
    function mintPosition(uint32 _nftfiId, bool _position, uint256 _leverage, uint256 _premium, uint256 _expiryUnix, uint256 _principal, uint8 _v, bytes32 _r, bytes32 _s) public payable {
        /// msg.value == margin
        bytes32 message = keccak256(abi.encodePacked(msg.value, _nftfiId, _position, _leverage, _premium, _expiryUnix, _principal));
        require(ecrecover(message, _v, _r, _s) == owner(), "Invalid signature or parameters");

        ++positionIdCounter;
        _safeMint(msg.sender, positionIdCounter);

        positionData[positionIdCounter] = LoanPosition({
            position: _position,
            margin: msg.value,
            leverage: _leverage / 1 ether,
            premium: _premium,
            expiryUnix: _expiryUnix,
            principal: _principal,
            nftfiId: _nftfiId
        });
    }

    /**
    * @notice Returns the URL of a token's metadata.
    * @param _tokenId Token ID
    **/
    function tokenURI(uint256 _tokenId)
        public
        view
        virtual
        override
        returns (string memory)
    {
        require(_ownerOf[_tokenId] != address(0), "Non-existent token URI");
        return
            bytes(baseURI).length > 0
                ? string(abi.encodePacked(baseURI, _tokenId.toString()))
                : "";
    }

    /**
    * @notice Triggers the loan position after loan reaches maturity
    * @param _tokenId ID of the position 
    **/
    function triggerPosition(uint256 _tokenId) external nonReentrant returns (bytes32) {
        require(_ownerOf[_tokenId] != address(0), "Position does not exist");
        require(block.timestamp > positionData[_tokenId].expiryUnix, "Loan not expired");
        
        return requestPrice(_tokenId);
    }

    /**
    * @dev Creates a Chainlink request to retrieve API response to validate the collateral price.
    * @param _tokenId ID of the position
    **/
    function requestPrice(uint256 _tokenId) private returns (bytes32) {
        Chainlink.Request memory req = buildChainlinkRequest(jobId, address(this), this.fulfill.selector);

        // Set the URL to perform the GET request on
        req.add('get', string.concat('https://app.gradient.city/api/', Strings.toString(positionData[_tokenId].nftfiId)));

        req.add('path', 'val'); // Chainlink nodes 1.0.0 and later support this format

        int256 timesAmount = 1;
        req.addInt('times', timesAmount);

        // Sends the request
        bytes32 sendRequest = sendChainlinkRequest(req, fee);
        requestToPosition[sendRequest] = _tokenId;
        return sendRequest;
    }

    /**
    * @notice Runs the position using the requested price.
    * @param _tokenId ID of the position 
    **/
    function activateProtection(uint256 _tokenId, uint256 _price, uint256 _repaid) private {
        require(_ownerOf[_tokenId] != address(0), "Position does not exist");
        address receiverPosition = _ownerOf[_tokenId];
        _burn(_tokenId);

        /// Position is long
        if (positionData[_tokenId].position) {
            if (_price >= positionData[_tokenId].principal) {
                /// Loan did not end at a loss.
                uint256 payback = positionData[_tokenId].margin + positionData[_tokenId].premium;
                
                /// Return margin + premium
                (bool transferTx, ) = receiverPosition.call{value: payback}("");
                require(transferTx, "Payback transfer failed.");
            }
            else if (_repaid == 0) {
                /// Loan took a loss.
                uint256 payback = max(0, positionData[_tokenId].margin + positionData[_tokenId].premium 
                    - (positionData[_tokenId].principal - _price) * positionData[_tokenId].leverage);

                if (payback > 0) {
                    (bool transferTx, ) = receiverPosition.call{value: payback}("");
                    require(transferTx, "Payback transfer failed.");
                }
            } else {
                /// Position is canceled because of the edge case, so the margin is returned.
                uint256 payback = positionData[_tokenId].margin;
                
                /// Return margin + premium
                (bool transferTx, ) = receiverPosition.call{value: payback}("");
                require(transferTx, "Payback transfer failed.");
            }
        }

        /// Position is short
        else {
            if (_price < positionData[_tokenId].principal) {
                if (_repaid == 0) {
                    /// Loan took a loss.
                    uint256 payback = min(positionData[_tokenId].margin, (positionData[_tokenId].principal - _price) * positionData[_tokenId].leverage);
                    
                    (bool transferTx, ) = receiverPosition.call{value: payback}("");
                    require(transferTx, "Payback transfer failed.");
                } else {
                    /// Position is canceled because of the edge case, so the premium is returned.
                    uint256 payback = positionData[_tokenId].premium;
                    
                    (bool transferTx, ) = receiverPosition.call{value: payback}("");
                    require(transferTx, "Payback transfer failed.");
                }
            }
        }
    }

    /**
    * @dev Recieves oracle response in the form of uint256.
    * @param _requestId Chainlink request ID
    * @param _value Fetched price of collateral (wei) and repayment state
    **/
    function fulfill(bytes32 _requestId, uint256 _value) public recordChainlinkFulfillment(_requestId) {
        emit RequestedPrice(_requestId, _value);

        // state = 1 --> repaid
        // state = 0 --> not repaid
        uint256 _repaid = _value % 10;
        uint256 _price = (_value / 10) % (10 ** (bytes(Strings.toString(_value)).length - 1));

        activateProtection(requestToPosition[_requestId], _price, _repaid);
    }

    /**
    * @notice Allows owner to withdraw LINK tokens.
    **/
    function withdrawLink() external onlyOwner {
        LinkTokenInterface link = LinkTokenInterface(chainlinkTokenAddress());
        require(link.transfer(owner(), link.balanceOf(address(this))), 'Unable to transfer');
    }

    /**
    * @notice Allows owner to withdraw allocated liquidity by Gradient.
    **/
    function withdrawAllocation(uint256 _amount) external onlyOwner {
        (bool transferTx, ) = owner().call{value: _amount}("");
        require(transferTx, "Withdraw allocation transfer failed.");
    }

    /**
    * @notice Allows owner to redefine Chainlink variables.
    **/
    function redefineChainlink(bytes32 _id, uint256 _fee) external onlyOwner {
        jobId = _id;
        fee = _fee;
    }
    
    /**
    * @notice Fallback function to receive ether allocated from Gradient.
    **/
    receive() external payable {}
}
