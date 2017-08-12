pragma solidity ^0.4.10;

/*
    Copyright 2017, Bezalel Lim, Artstock Exchange Inc.

    This program is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */

/// @title SnapshotableDividendableToken Contract
/// @author Bezalel Lim <bezalel@artstockx.com> <bezalel.dev@gmail.com>
/// @dev TODO documentation

import "./SnapshotableToken.sol";

contract IERC20Transfer {
    function transfer(address _to, uint256 _value) returns (bool success);
}

contract SnapshotableDividendableToken is SnapshotableToken, IERC223TokenReceiver {

    // the authorized dividend disburser.
    // only the `dividendDisburser` account can transfer ERC223 compatible tokens to this 'Dividendable' token contract
    // as dividend disbursement.
    address public dividendDisburser;

    struct DividendDisbursement {
        uint128 blockNum;
        uint128 amount;
    }

    /// @dev dividend claim status data for each account
    struct DividendClaimStatus {
        uint128 nextDividendIndexToClaim;
        uint128 claimedDividendAmount;
    }

    struct DividendToken {
        uint128 totalDividends;
        uint128 totalClaimedDividends;
        DividendDisbursement[] dividendDisbursementHistory;
        mapping(address => DividendClaimStatus) dividendClaims;
    }

    mapping (address => DividendToken) dividendTokens;
    address[] public dividendTokenList;

    /// @dev log event that will be fired when new dividend disbursement fund is deposited on this 'Dividendable' token contract
    /// @param _dividendToken the ERC223-compatible token contract address whose tokens are used as dividend disbursement funds
    /// @param _amount the amount of token deposited on this token contract as dividend disbursement funds
    /// @param _data custom data that can be stored on dividend event. it can be empty
    event NewDividend(address indexed _dividendToken, uint256 _amount, bytes _data);
    /// @dev log event that will be fired when a token-holder claims his/her dividend for
    /// @param _tokenHolder TODO
    /// @param _dividendToken TODO
    /// @param _amount TODO
    event ClaimedDividend(address indexed _tokenHolder, address indexed _dividendToken, uint256 _amount);

    // @dev SnapshotableDividendableToken constructor
    function SnapshotableDividendableToken(
        address _tokenFactory,
        address _parentToken,
        uint256 _parentSnapshotBlock,
        string _tokenName,
        uint8 _decimalUnits,
        string _tokenSymbol,
        bool _transfersEnabled,
        address _dividendDisburser
    ) SnapshotableToken(_tokenFactory, _parentToken, _parentSnapshotBlock,
        _tokenName, _decimalUnits, _tokenSymbol, _transfersEnabled) {

        dividendDisburser = _dividendDisburser;
    }

    function setDividendDisburser(address _newDisburser)
        non_zero_address(_newDisburser)
        only(dividendDisburser)
        public {

        dividendDisburser = _newDisburser;
    }

    /// @dev ERC223 token receiver interface (a function to handle token transfers that is called
    ///    from token contract when token holder is sending tokens.)
    ///    this token receives ERC223 tokens as dividend disbursement funds that will be distributed to token holders.
    ///    only the authorized account can transfer dividend funds to this token.
    /// @param _from The token sender
    /// @param _value The amount of incoming tokens
    /// @param _data attached custom data similar to data in Ether transactions. works like fallback function for
    function tokenFallback(address _from, uint _value, bytes _data) {
        require(_from == dividendDisburser);
        require(_value > 0);
        uint128 amount = cast128(_value);

        DividendToken storage dividendToken = dividendTokens[msg.sender];
        if (dividendToken.totalDividends == 0) {
            // first time dividend for the current type of dividend token(ERC223, msg.sender),
            // so register to `dividendTokenList`
            dividendTokenList[dividendTokenList.length++] = msg.sender; // appends last entry
        }
        dividendToken.totalDividends = add128(dividendToken.totalDividends, amount);
//        dividendToken.unclaimedDividends = add128(dividendToken.unclaimedDividends, amount);
        DividendDisbursement[] storage disbursementHistory = dividendToken.dividendDisbursementHistory;
        DividendDisbursement storage newDividendDisbursementEntry = disbursementHistory[disbursementHistory.length++];
        newDividendDisbursementEntry.blockNum = uint128(block.number); // distinct block number is guaranteed by `snapshot()`
        newDividendDisbursementEntry.amount = amount;

        // snapshot the token distribution at current block number for dividend-claiming method to retrieve the exact
        // token balance of the requested account and total supply of this token at the dividend block.
        snapshot();

        NewDividend(msg.sender, _value, _data);
    }

    /// @notice Claim the token-holder's accumulated dividend disbursed by the token type of `_token`
    /// @param _dividendToken The ERC20/ERC223-compatible token address registered in `dividendTokenList`.
    ///    token holders take their dividend by getting tokens of '_dividendToken' type.
    /// @param _maxDisbursementCheckCount if 0, all unclaimed dividend disbursement is checked.
    ///    because of the gas limit, in an extreme situation, dividend amount calculation for the indefinite number of dividend disbursement
    ///    could be not completed. so there can be the cases of partial dividend claim or claim failure by gas limit exception.
    ///    To securely claim all dividends allocated to an account, the token holder can execute `claimDividend` again with none-zero `_maxDisbursementCheckCount`
    ///    to additionally claim or re-claim the remaining unclaimed dividend amount.
    /// @return The claimed amount of `_dividendToken` token. this amount of token is transferred
    ///    to the requesting account(the token holder of this 'Dividendable' token)
    function claimDividend(address _dividendToken, uint _maxDisbursementCheckCount) returns (uint256) {

        DividendToken storage dividendToken = dividendTokens[_dividendToken];
        if (dividendToken.totalDividends == 0) { return 0; }

        DividendClaimStatus storage claimStatus = dividendToken.dividendClaims[msg.sender];
        uint startIdx = claimStatus.nextDividendIndexToClaim;
        uint endIdx = dividendToken.dividendDisbursementHistory.length;

        if (startIdx >= endIdx) { return 0; }

        if (_maxDisbursementCheckCount > 0 && (endIdx - startIdx > _maxDisbursementCheckCount)) {
            endIdx = startIdx + _maxDisbursementCheckCount;
        }

        uint256 claimed = accumulateDividendTokenAmountToClaim(dividendToken, startIdx, endIdx);
        claimStatus.nextDividendIndexToClaim = uint128(endIdx);

        if (claimed == 0) { return 0; }

        uint128 hClaimed = uint128(claimed); // no overflow
        claimStatus.claimedDividendAmount += hClaimed; // no overflow always capped by uint128 dividendToken.totalDividends
        dividendToken.totalClaimedDividends += hClaimed;  // no overflow always capped by uint128 dividendToken.totalDividends

        // TODO check if transfer tx should be separate method
        require(IERC20Transfer(_dividendToken).transfer(msg.sender, claimed));

        ClaimedDividend(msg.sender, _dividendToken, claimed);
        return claimed;
    }

    function accumulateDividendTokenAmountToClaim(DividendToken storage _dividendTokenData, uint _startIndex, uint _endIndex) constant internal returns (uint256) {
        uint256 amountToClaim = 0;
        DividendDisbursement[] storage disbursementHistory = _dividendTokenData.dividendDisbursementHistory;
        for (uint i = _startIndex; i < _endIndex; i++) {
            DividendDisbursement storage disbursement = disbursementHistory[i];
            uint256 blockNumAt = uint256(disbursement.blockNum);
            uint256 balanceAtDividendBlock = balanceOfAt(msg.sender, blockNumAt); // balanceAt is in unsigned 128bit range
            uint256 totalSupplyAtDividendBlock = totalSupplyAt(blockNumAt); // totalSupplyAt is in unsigned 128bit range
            uint256 dividendToClaim = (disbursement.amount * balanceAtDividendBlock) / totalSupplyAtDividendBlock; // no overflow is guaranteed
            amountToClaim += dividendToClaim;
        }
        return amountToClaim; // amountToClaim is in uint128 range (capped by uint128 dividendToken.totalDividends)
    }

    function getDividendTokenCount() constant returns (uint256) {
        return dividendTokenList.length;
    }

    function getDividendTokenStatus(address _dividendToken) constant returns (uint256 totalDividendTokenAmount, uint256 totalClaimedDividendTokenAmount) {
        DividendToken storage dividendToken = dividendTokens[_dividendToken];
        totalDividendTokenAmount = uint256(dividendToken.totalDividends);
        totalClaimedDividendTokenAmount = uint256(dividendToken.totalClaimedDividends);
    }

    function getDividendClaimStatus(address _dividendToken, address _tokenHolder) constant returns (uint256 claimedDividendTokenAmount, uint256 unclaimedDividendDisbursementCount) {
        DividendToken storage dividendToken = dividendTokens[_dividendToken];
        DividendClaimStatus storage claimStatus = dividendToken.dividendClaims[_tokenHolder];
        claimedDividendTokenAmount = uint256(claimStatus.claimedDividendAmount);
        unclaimedDividendDisbursementCount = dividendToken.dividendDisbursementHistory.length - uint256(claimStatus.nextDividendIndexToClaim);
    }

    function getUnclaimedDividendTokenAmount(address _dividendToken, address _tokenHolder) constant returns (uint256) {
        DividendToken storage dividendToken = dividendTokens[_dividendToken];
        DividendClaimStatus storage claimStatus = dividendToken.dividendClaims[_tokenHolder];
        uint startIdx = claimStatus.nextDividendIndexToClaim;
        uint endIdx = dividendToken.dividendDisbursementHistory.length;
        if (startIdx >= endIdx) { return 0; }
        return accumulateDividendTokenAmountToClaim(dividendToken, startIdx, endIdx);
    }

    modifier only(address x) {
        assert(msg.sender == x);
        _;
    }

    modifier non_zero_address(address x) {
        assert(x != 0);
        _;
    }

    function add128(uint128 x, uint128 y) constant internal returns (uint128 z) {
        assert((z = x + y) >= x);
    }
}