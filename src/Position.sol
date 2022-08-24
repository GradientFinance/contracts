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
    mapping(address => uint256) public allocatedLiquidity;

    event RequestedFloor(bytes32 indexed _requestId, uint256 _floor);

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
    * @param _signature Address deployer signature of parameters.
    **/
    function mintPosition(uint32 _nftfiId, bool _position, uint256 _leverage, uint256 _premium, uint256 _expiryUnix, uint256 _principal, bytes memory _signature) public payable {
        /// msg.value == margin
        bytes32 message = keccak256(abi.encodePacked(msg.value, _nftfiId, _position, _leverage, _premium, _expiryUnix, _principal));
        require(recoverSigner(message, _signature) == owner(), "Invalid signature or parameters");

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
    function triggerPosition(uint256 _tokenId) external nonReentrant {
        require(_ownerOf[_tokenId] != address(0), "Position does not exist");
        require(block.timestamp > positionData[_tokenId].expiryUnix, "Loan not expired");
        
        requestFloor(_tokenId);
    }

    /**
    * @dev Creates a Chainlink request to retrieve API response to validate the collateral floor.
    * @param _tokenId ID of the position
    **/
    function requestFloor(uint256 _tokenId) private {
        Chainlink.Request memory req = buildChainlinkRequest(jobId, address(this), this.fulfill.selector);

        // Set the URL to perform the GET request on
        req.add('get', string.concat('https://app.gradient.city/api/', Strings.toString(positionData[_tokenId].nftfiId)));

        req.add('path', 'floor'); // Chainlink nodes 1.0.0 and later support this format

        int256 timesAmount = 1;
        req.addInt('times', timesAmount);

        // Sends the request
        bytes32 sendRequest = sendChainlinkRequest(req, fee);
        requestToPosition[sendRequest] = _tokenId;
    }

    /**
    * @notice Runs the position using the requested floor.
    * @param _tokenId ID of the position 
    **/
    function activateProtection(uint256 _tokenId, uint256 _floor) private {
        require(_ownerOf[_tokenId] != address(0), "Position does not exist");
        address receiverPosition = _ownerOf[_tokenId];

        /// Position is long
        if (positionData[_tokenId].position) {
            if (_floor >= positionData[_tokenId].principal) {
                /// Loan did not end at a loss.
                uint256 payback = positionData[_tokenId].margin + positionData[_tokenId].premium;
                _burn(_tokenId);
                
                /// Return margin + premium
                (bool transferTx, ) = receiverPosition.call{value: payback}("");
                require(transferTx, "Payback transfer failed.");
            }
            else {
                /// Loan took a loss.
                if (_floor > (positionData[_tokenId].margin + positionData[_tokenId].premium) / positionData[_tokenId].leverage) {
                    /// The position wasn't completely wiped, so the user can get some of their funds back.
                    uint256 payback = max(0, positionData[_tokenId].margin + positionData[_tokenId].premium - (positionData[_tokenId].principal - _floor) * positionData[_tokenId].leverage);
                    _burn(_tokenId);
                    
                    (bool transferTx, ) = receiverPosition.call{value: payback}("");
                    require(transferTx, "Payback transfer failed.");
                }
                else {
                    /// The position was completely wiped, so the user loses the margin and the premium.
                    _burn(_tokenId);
                }
            }
        }

        /// Position is short
        else {
            if (_floor >= positionData[_tokenId].principal) {
                /// Loan did not end at a loss, so the user loses the premium they had spent.
                _burn(_tokenId);
            }
            else {
                /// Loan took a loss.
                if (_floor > (positionData[_tokenId].margin + positionData[_tokenId].premium) / positionData[_tokenId].leverage) {
                    /// The position wasn't completely wiped, so the user can get some of their funds back.
                    uint256 payback = positionData[_tokenId].margin + positionData[_tokenId].premium - (positionData[_tokenId].principal - _floor) * positionData[_tokenId].leverage;
                    _burn(_tokenId);
                    
                    (bool transferTx, ) = receiverPosition.call{value: payback}("");
                    require(transferTx, "Payback transfer failed.");
                }
                else {
                    /// Loan took a loss.
                    uint256 payback = min(positionData[_tokenId].margin, (positionData[_tokenId].principal - _floor) * positionData[_tokenId].leverage);
                    _burn(_tokenId);
                    
                    (bool transferTx, ) = receiverPosition.call{value: payback}("");
                    require(transferTx, "Payback transfer failed.");
                }
            }
        }
    }

    /**
    * @dev Recieves oracle response in the form of uint256.
    * @param _requestId Chainlink request ID
    * @param _floor Fetched floor of collateral (wei)
    **/
    function fulfill(bytes32 _requestId, uint256 _floor) public recordChainlinkFulfillment(_requestId) {
        emit RequestedFloor(_requestId, _floor);
        activateProtection(requestToPosition[_requestId], _floor);
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
    function withdrawAllocation() external onlyOwner {
        (bool transferTx, ) = owner().call{value: allocatedLiquidity[owner()]}("");
        require(transferTx, "Withdraw allocation transfer failed.");
    }

    /**
    * @notice Fallback function to receive ether allocated from Gradient.
    **/
    receive() external payable {
        allocatedLiquidity[owner()] = allocatedLiquidity[owner()] += msg.value;
    }
}
