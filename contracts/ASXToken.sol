pragma solidity ^0.4.10;

import "./SnapshotableToken.sol";

contract ASXToken is SnapshotableToken {
    // @dev ASXToken constructor just parametrizes the SnapshotableToken constructor
    function ASXToken(
        address _tokenFactory
    ) SnapshotableToken(
        _tokenFactory,
        0x0,                    // no parent token
        0,                      // no snapshot block number from parent
        "Artstock Exchange Token", // Token name
        18,                     // Decimals
        "ASX",                  // Symbol
        true                    // Enable transfers
    ) {}
}