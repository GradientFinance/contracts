// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import 'chainlink/contracts/src/v0.8/ChainlinkClient.sol';
import "openzeppelin-contracts/contracts/access/Ownable.sol";
import "openzeppelin-contracts/contracts/utils/Strings.sol";
import './helpers.sol';

/**
 * Request testnet LINK and ETH here: https://faucets.chain.link/
 * Find information on LINK Token Contracts and get the latest ETH and LINK faucets here: https://docs.chain.link/docs/link-token-contracts/
 */

/**
 * THIS IS AN EXAMPLE CONTRACT WHICH USES HARDCODED VALUES FOR CLARITY.
 * PLEASE DO NOT USE THIS CODE IN PRODUCTION.
 */
contract APIConsumer is ChainlinkClient, Ownable, Helpers {
    using Strings for uint256;
    using Chainlink for Chainlink.Request;

    mapping(address => mapping(uint256 => uint256)) public price;
    mapping(bytes32 => address) internal requestToAddress;
    mapping(bytes32 => uint256) internal requestToId;
    bytes32 private jobId;
    uint256 private fee;

    event RequestPrice(bytes32 indexed requestId, uint256 price);

    /**
     * @notice Initialize the link token and target oracle
     *
     * Rinkeby Testnet details:
     * Link Token: 0x01BE23585060835E02B77ef475b0Cc51aA1e0709
     * Oracle: 0xf3FBB7f3391F62C8fe53f89B41dFC8159EE9653f (Chainlink DevRel)
     * jobId: ca98366cc7314957b8c012c72f05aeeb
     *
     */
    constructor() {
        setChainlinkToken(0x01BE23585060835E02B77ef475b0Cc51aA1e0709);
        setChainlinkOracle(0xf3FBB7f3391F62C8fe53f89B41dFC8159EE9653f);
        jobId = 'ca98366cc7314957b8c012c72f05aeeb';
        fee = (1 * LINK_DIVISIBILITY) / 10; // 0,1 * 10**18 (Varies by network and job)
    }

    /**
     * Create a Chainlink request to retrieve API response, find the target
     * data, then multiply by 1000000000000000000 (to remove decimal places from data).
     */
    function _RequestPrice(address contractAddress, uint256 tokenId) public {
        Chainlink.Request memory req = buildChainlinkRequest(jobId, address(this), this.fulfill.selector);

        // Set the URL to perform the GET request on
        string memory s = string.concat('http://disestevez.pythonanywhere.com/', _toAsciiString(contractAddress));
        s = string.concat(s, "/");
        s = string.concat(s, Strings.toString(tokenId));
        req.add('get', s);

        req.add('path', 'price'); // Chainlink nodes 1.0.0 and later support this format

        // Multiply the result by 1000000000000000000 to remove decimals
        int256 timesAmount = 10**18;
        req.addInt('times', timesAmount);

        // Sends the request
        bytes32 sendRequest = sendChainlinkRequest(req, fee);
        requestToAddress[sendRequest] = contractAddress;
        requestToId[sendRequest] = tokenId;
    }

    /**
     * Receive the response in the form of uint256
     */
    function fulfill(bytes32 _requestId, uint256 _price) public recordChainlinkFulfillment(_requestId) {
        emit RequestPrice(_requestId, _price);
        price[requestToAddress[_requestId]][requestToId[_requestId]] = _price;
    }

    /**
     * Allow withdraw of Link tokens from the contract
     */
    function withdrawLink() public onlyOwner {
        LinkTokenInterface link = LinkTokenInterface(chainlinkTokenAddress());
        require(link.transfer(msg.sender, link.balanceOf(address(this))), 'Unable to transfer');
    }
}
