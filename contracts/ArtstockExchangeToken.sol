pragma solidity ^0.4.10;

import "./SnapshotableDividendableToken.sol";

contract ArtstockExchangeToken is SnapshotableDividendableToken {
    // @dev ArtstockExchangeToken constructor just parametrizes the SnapshotableDividendableToken constructor
    function ArtstockExchangeToken(
        address _tokenFactory,
        address _dividendDisburser
    ) SnapshotableDividendableToken(
        _tokenFactory,
        0x0,                    // no parent token
        0,                      // no snapshot block number from parent
        "Artstock Exchange Token", // Token name
        18,                     // Decimals
        "ASX",                  // Symbol
        true,                   // Enable transfers
        _dividendDisburser      // dividend-disburser multisig address
    ) {}
}