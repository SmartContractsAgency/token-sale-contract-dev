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
/// @author Bezalel Lim <bezalel@artstockx.com>
/// @dev SnapshotableDividendableToken is a derived version of SnapshotableToken upon which the dividend feature is implemented.
///   The token holders can claim their own portion of dividend tokens disbursed/transferred by `dividendDisburser` account.
///   The dividend funds are disbursed by using any ERC20/ERC223-compatible standard tokens, so SnapshotableDividendableToken
///   receives the disbursed dividend tokens through the `tokenFallback` function of ERC223 standard interface.
///   The `dividendDisburser` can disburse(transfer) the multiple types of ERC20/ERC223 dividend tokens to this token contract multiple times,
///   and the token holders can claim the accrued amount of multiple dividends in proportion to their own token amount
///   "snapshotted" at the exact same time(block number) of each dividend disbursement event.
///   To prevent the dividend tokens not to be lost in this token contract, the accumulated tiny rounding errors and
///   the dividends unclaimed for a long time can be taken back (deactivated) by `dividendDisburser` account
///   after a lapse of predefined `dividendDeactivateTimeLimit`.

import "./SnapshotableToken.sol";

/// @dev interface for ERC transfer function used by SnapshotableDividendableToken when dividend tokens are transferred
contract IERC20Transfer {
    /// @notice Send `_value` tokens to `_to` from `msg.sender`
    /// @param _to The address of the recipient
    /// @param _value The amount of tokens to be transferred
    /// @return Whether the transfer was successful or not
    function transfer(address _to, uint256 _value) returns (bool success);
}

contract SnapshotableDividendableToken is SnapshotableToken, IERC223TokenReceiver {

    /// @dev For each type of ERC20/ERC223 dividend tokens disbursed to this token contract, `DividendToken` data structure is managed.
    ///   DividendToken holds all the states of dividend token including total/claimed dividend amounts,
    ///   all dividend history, each token-holder's dividend claim status and deactivated dividends.
    struct DividendToken {
        // the accumulated total dividend token amount of this ERC223 dividend token type.
        // `totalDividendAmount` equals to the sum of `dividendDisbursementHistory.dividendAmount`
        uint128 totalDividendAmount;
        // the accumulated total dividend token amount claimed by token holders
        // `totalClaimedDividendAmount` equals to the sum of `dividendDisbursementHistory.claimedAmount`,
        // and also equals to the sum of `dividendClaims[all-accounts].claimedDividendAmount`
        uint128 totalClaimedDividendAmount;
        // the last deactivated(taken-back) dividend index on `dividendDisbursementHistory`.
        // the index value starts from 1 (0 : there is no deactivated dividend)
        // `DividendDisbursement` can be deactivated only if all the previous `DividendDisbursement`
        // in `dividendDisbursementHistory` were already deactivated.
        uint128 lastDeactivatedDividendIndex;
        // array of all dividend disbursement event of this dividend token type.
        // ordered by disbursement time(`DividendDisbursement.blockNum`)
        DividendDisbursement[] dividendDisbursementHistory;
        // for each token holder account, dividend claim states are tracked.
        mapping(address => DividendClaimStatus) dividendClaims;
    }

    /// @dev For each dividend token disbursement by the authorized `dividendDisburser`,
    ///   `DividendDisbursement` struct is added to `DividendToken.dividendDisbursementHistory`
    struct DividendDisbursement {
        // the dividend token amount transferred by `dividendDisburser` for this dividend disbursement
        uint128 dividendAmount;
        // the total dividend token amount claimed by token holders for this dividend disbursement
        uint128 claimedAmount;
        // block number at which this dividend disbursement occurs (block number of the Ethereum transaction executing `tokenFallback`)
        uint128 blockNum;
        // block timestamp as seconds since unix epoch of this dividend disbursement transaction (timestamp of `blockNum`)
        uint64 timestamp;
        // after `dividendDeactivateTimeLimit` (e.g. 2 years) from the `timestamp` of the dividend disbursement,
        // the authorized `dividendDisburser` can take back the remaining dividend amount consisting of
        // the accumulated tiny rounding errors and the dividends unclaimed for a long time, and deactivate
        // claiming dividend from this disbursement. `DividendDisbursement` can be deactivated only if all the previous
        // `DividendDisbursement` in `dividendDisbursementHistory` were already deactivated.
        bool deactivated;
    }

    /// @dev Dividend token claim status data for each account
    struct DividendClaimStatus {
        // next dividend disbursement index in `DividendToken.dividendDisbursementHistory` to claim next time.
        // index value starts from 0
        // * nextDividendIndexToClaim == 0 : token holder account didn't claimed any token of the dividend token type of `DividendToken`
        // * nextDividendIndexToClaim == dividendDisbursementHistory.lendth : token holder account has claimed
        //     all available tokens of the dividend token type of `DividendToken`
        uint128 nextDividendIndexToClaim;
        // the accumulated dividend token amount that token holder account has claimed for the dividend token type of `DividendToken`
        uint128 claimedDividendAmount;
    }

    // the authorized dividend disburser.
    // only the `dividendDisburser` account can transfer ERC223 compatible tokens to this 'Dividendable' token contract
    // as dividend disbursement.
    address public dividendDisburser;

    // for each type of dividend tokens disbursed to this token contract, DividendToken data structure is managed.
    mapping (address => DividendToken) dividendTokens;
    // all dividend token addresses are stored here, so all disbursed token types can be retrieved by token holders
    address[] public dividendTokenList;

    // the dividend deactivation time limit in seconds
    // the accumulated tiny rounding errors and the dividends unclaimed for a long time
    // can be taken back by `dividendDisburser` account after a lapse of `dividendDeactivateTimeLimit` time period.
    uint64 public dividendDeactivateTimeLimit;

    /// @dev Log event fired when new dividend token fund(`_amount` of `_dividendToken` type) is disbursed/transferred on this token contract
    /// @param _dividendToken the ERC20/ERC223 token contract address whose tokens are used as dividend disbursement funds
    /// @param _amount the amount of token deposited on this token contract as dividend disbursement fund
    /// @param _data custom data that can be stored on dividend event. it can be empty
    event NewDividend(address indexed _dividendToken, uint256 _amount, bytes _data);
    /// @dev Log event fired when `_tokenHolder` claims his/her dividend token `_amount` for `_dividendToken` type
    /// @param _tokenHolder The token holder account address
    /// @param _dividendToken The dividend token contract address
    /// @param _amount The dividend token amount to be claimed
    event ClaimedDividend(address indexed _tokenHolder, address indexed _dividendToken, uint256 _amount);
    /// @dev Log event fired when a dividend disbursement of `_dividendToken` type is deactivated by `dividendDisburser`
    ///   taking back the remaining dividend amount including the accumulated tiny rounding errors and the dividends unclaimed for a long time
    /// @param _dividendToken The dividend token contract address
    /// @param _disbursementIndex The deactivated(taken-back) dividend index on `DividendToken.dividendDisbursementHistory`.
    ///   the index value starts from 1 (1 : indicating `DividendToken.dividendDisbursementHistory[0]`)
    /// @param _remainingAmount The remaining dividend token amount which is sum of the accrued rounding errors
    ///   and the unclaimed dividends at this deactivation event
    event DeactivatedDividendDisbursement(address indexed _dividendToken, uint256 _disbursementIndex, uint256 _remainingAmount);

    /// @notice SnapshotableDividendableToken constructor
    /// @param _tokenFactory The address of the SnapshotableTokenFactory contract that
    ///   will create the Clone token contracts, the token factory needs to be deployed first
    /// @param _parentToken Address of the parent token, set to 0x0 if it is a new token
    /// @param _parentSnapshotBlock Block number of the parent token that will determine
    ///   the initial distribution of the clone token, set to 0 if it is a new token
    /// @param _tokenName Name of the new token
    /// @param _decimalUnits Number of decimals of the new token
    /// @param _tokenSymbol Token Symbol for the new token
    /// @param _transfersEnabled If true, tokens will be able to be transferred
    /// @param _dividendDisburser The authorized dividend disburser
    /// @param _dividendDeactivateTimeLimit The dividend deactivation time limit in seconds
    function SnapshotableDividendableToken(
        address _tokenFactory,
        address _parentToken,
        uint256 _parentSnapshotBlock,
        string _tokenName,
        uint8 _decimalUnits,
        string _tokenSymbol,
        bool _transfersEnabled,
        address _dividendDisburser,
        uint64 _dividendDeactivateTimeLimit
    ) SnapshotableToken(_tokenFactory, _parentToken, _parentSnapshotBlock,
        _tokenName, _decimalUnits, _tokenSymbol, _transfersEnabled) {

        assert(_dividendDisburser != 0);

        dividendDisburser = _dividendDisburser;
        dividendDeactivateTimeLimit = _dividendDeactivateTimeLimit;
    }

    /// @notice Change `dividend disburser' account to new account. Only the current 'dividend disburser' account can execute this.
    /// @param _newDisburser Ethereum account address for new 'dividend disburser'
    function setDividendDisburser(address _newDisburser)
        non_zero_address(_newDisburser)
        only(dividendDisburser) public {

        dividendDisburser = _newDisburser;
    }

    /// @notice Change the dividend disbursement deactivation time limit value in seconds. Only the current 'dividend disburser' account can execute this.
    /// @param _newTimeLimit The new dividend disbursement deactivation time limit in seconds
    function setDividendDeactivateTimeLimit(uint64 _newTimeLimit)
        only(dividendDisburser) public {
        dividendDeactivateTimeLimit = _newTimeLimit;
    }

    /// @dev ERC223 token receiver interface (a function to handle token transfers that is called
    ///    from ERC223 token contract when token holder is sending tokens to this ERC223 receiver contract account)
    ///    this token receives ERC223 tokens as dividend disbursement funds that will be distributed to token holders.
    ///    only the authorized `dividendDisburser` account can transfer dividend tokens to this token contract.
    /// @param _from The token sender. Only the `dividendDisburser` account is allowed
    /// @param _value The amount of incoming tokens
    /// @param _data The attached custom data similar to data in Ether transactions.
    ///   It can be used for storing hash value pointing to the data related to dividend disbursement event.
    function tokenFallback(address _from, uint _value, bytes _data) {
        require(_from == dividendDisburser);
        require(_value > 0);
        uint128 amount = cast128(_value);

        DividendToken storage dividendToken = dividendTokens[msg.sender];
        if (dividendToken.totalDividendAmount == 0) {
            // first time dividend for the current type of dividend token(ERC223, msg.sender),
            // so register to `dividendTokenList`
            dividendTokenList[dividendTokenList.length++] = msg.sender; // appends last entry
        }
        dividendToken.totalDividendAmount = add128(dividendToken.totalDividendAmount, amount);
        DividendDisbursement[] storage disbursementHistory = dividendToken.dividendDisbursementHistory;
        DividendDisbursement storage newDividendDisbursementEntry = disbursementHistory[disbursementHistory.length++];
        newDividendDisbursementEntry.dividendAmount = amount;
        //newDividendDisbursementEntry.claimedAmount = 0; // default zero
        newDividendDisbursementEntry.blockNum = uint128(block.number); // distinct block number is guaranteed by `snapshot()`
        newDividendDisbursementEntry.timestamp = uint64(block.timestamp);
        //newDividendDisbursementEntry.deactivated = false; // default zero

        // execute snapshot() function inherited from SnapshotableToken contract
        // snapshot the token distribution at current block number for `claimDividend` method to retrieve the exact
        // token balance of the requested account and the exact total supply value of this token contract
        // at the dividend disbursement event block.
        require(snapshot());

        NewDividend(msg.sender, _value, _data);
    }

    /// @notice Claim the token-holder's accumulated dividend tokens of `_dividendToken` type in proportion to the holder's own token amount
    /// @param _dividendToken The ERC20/ERC223-compatible token address registered in `dividendTokenList`.
    ///    token holders take their dividend by getting tokens of '_dividendToken' type.
    /// @param _maxDisbursementCheckCount if 0, all unclaimed dividend disbursement is checked.
    ///    because of the gas limit, in an extreme situation, dividend amount calculation for the indefinite number of dividend disbursement
    ///    could be not completed. so there can be the cases of partial dividend claim or claim failure by gas limit exception.
    ///    To securely claim all dividends allocated to an account, the token holder can execute `claimDividend` again with none-zero `_maxDisbursementCheckCount`
    ///    to additionally claim or re-claim the remaining unclaimed dividend amount.
    /// @return The claimed amount of `_dividendToken` token. this amount of token is transferred
    ///    to the requesting account(the token holder of this 'Dividendable' token)
    function claimDividend(address _dividendToken, uint _maxDisbursementCheckCount) returns (uint) {

        DividendToken storage dividendToken = dividendTokens[_dividendToken];
        if (dividendToken.totalDividendAmount == 0) { return 0; }

        // token holder's dividend claim status for `'_dividendToken` type
        DividendClaimStatus storage claimStatus = dividendToken.dividendClaims[msg.sender];
        uint startIdx = claimStatus.nextDividendIndexToClaim;
        if (startIdx < dividendToken.lastDeactivatedDividendIndex) {
            // skip the deactivated dividend disbursements
            // `lastDeactivatedDividendIndex` index number starts from 1 (1 : indicating `dividendToken.dividendDisbursementHistory[0]`)
            startIdx = dividendToken.lastDeactivatedDividendIndex;
        }
        uint endIdx = dividendToken.dividendDisbursementHistory.length; // endIdx : (last 'to-be-claimed' dividend index) + 1

        if (startIdx >= endIdx) { return 0; } // there is nothing to claim

        if (_maxDisbursementCheckCount > 0 && (endIdx - startIdx > _maxDisbursementCheckCount)) {
            // to avoid gas limit exception, limit the count of disbursement item to be checked
            endIdx = startIdx + _maxDisbursementCheckCount;
            // always "startIdx < endIdx" holds true
        }

        // calculate the total token amount to claim, and update the claimed amount on each `DividendDisbursement`
        uint256 totalClaimed = accumulateDividendTokenAmountToClaim(dividendToken, startIdx, endIdx, true /*update 'claimed' balances*/);

        claimStatus.nextDividendIndexToClaim = uint128(endIdx);

        if (totalClaimed == 0) { return 0; }

        uint128 hTotalClaimed = uint128(totalClaimed); // half-word(128bit), no overflow
        claimStatus.claimedDividendAmount += hTotalClaimed; // no overflow always capped by uint128 dividendToken.totalDividendAmount
        dividendToken.totalClaimedDividendAmount += hTotalClaimed;  // no overflow always capped by uint128 dividendToken.totalDividendAmount

        // TODO check if transfer tx should be separate method
        require(IERC20Transfer(_dividendToken).transfer(msg.sender, totalClaimed));

        ClaimedDividend(msg.sender, _dividendToken, totalClaimed);
        return totalClaimed;
    }

    /// @notice Deactivate a dividend disbursement of `_dividendToken` type. Only the current 'dividend disburser' account can execute this.
    /// @dev To prevent the dividend tokens not to be lost in this token contract, the authorized `dividendDisburser`
    ///   can take back the remaining dividend amount consisting of the accumulated tiny rounding errors and the dividends
    ///   unclaimed for a long time. After `dividendDeactivateTimeLimit` (e.g. 2 years) from the `timestamp` of the dividend disbursement,
    ///   the stale dividend disbursement can be deactivated not allowing dividend claim from this disbursement afterwards.
    ///  `DividendDisbursement` can be deactivated only if all the previous `DividendDisbursement` in `dividendDisbursementHistory`
    ///   were already deactivated.
    /// @param _disbursementIndex The dividend index on `DividendToken.dividendDisbursementHistory` to be deactivated.
    ///   The index value starts from 1 (1 : indicating `DividendToken.dividendDisbursementHistory[0]`)
    /// @return The token amount taken back to `dividendDisburser` which is sum of the accrued rounding errors
    ///   and the unclaimed dividends at this deactivation transaction
    function deactivateDividendDisbursement(address _dividendToken, uint _disbursementIndex)
        only(dividendDisburser)
        returns (uint) {

        DividendToken storage dividendToken = dividendTokens[_dividendToken];
        if (dividendToken.totalDividendAmount == 0) { return 0; }

        // dividend disbursement to deactivate
        DividendDisbursement storage disbursement = dividendToken.dividendDisbursementHistory[_disbursementIndex - 1];
        // check deactivation time limit constraint
        require(block.timestamp > uint256(disbursement.timestamp + dividendDeactivateTimeLimit));

        if (_disbursementIndex > 1) { // if not the first dividend disbursement to deactivate
            // `DividendDisbursement` can be deactivated only if
            // all the previous `DividendDisbursement` in `dividendDisbursementHistory` were already deactivated.
            require(dividendToken.dividendDisbursementHistory[_disbursementIndex - 2].deactivated == true);
        }

        uint256 remaining = 0;
        if (disbursement.dividendAmount > disbursement.claimedAmount) {
            remaining = uint256(disbursement.dividendAmount - disbursement.claimedAmount);
        }
        disbursement.deactivated = true;
        dividendToken.lastDeactivatedDividendIndex = uint128(_disbursementIndex); // no overflow

        if (remaining > 0) {
            // the authorized `dividendDisburser` can take back the remaining dividend amount consisting of
            // the accumulated tiny rounding errors and the dividends unclaimed for a long time
            require(IERC20Transfer(_dividendToken).transfer(msg.sender, remaining));
        }

        DeactivatedDividendDisbursement(_dividendToken, _disbursementIndex, remaining);
        return remaining;
    }

    /// @dev helper function, calculate the total token amount that can be claimed.
    ///   Updating the claimed amount on each `DividendDisbursement` is optional for read-only operation.
    function accumulateDividendTokenAmountToClaim(
        DividendToken storage _dividendTokenData, uint _startIndex, uint _endIndex, bool _doClaim
    ) internal returns (uint256) {

        uint256 total = 0;
        DividendDisbursement[] storage disbursementHistory = _dividendTokenData.dividendDisbursementHistory;
        for (uint i = _startIndex; i < _endIndex; i++) {
            DividendDisbursement storage disbursement = disbursementHistory[i];
            uint256 blockNumAt = uint256(disbursement.blockNum);
            uint256 balanceAtDividendBlock = balanceOfAtCheckpoint(msg.sender, blockNumAt); // balanceAt is in uint128 range
            uint256 totalSupplyAtDividendBlock = totalSupplyAtCheckpoint(blockNumAt); // totalSupplyAt is in uint128 range
            uint256 dividendToClaim = (disbursement.dividendAmount * balanceAtDividendBlock) / totalSupplyAtDividendBlock; // no overflow and in uint128 range
            if (_doClaim) {
                disbursement.claimedAmount += uint128(dividendToClaim); // no overflow
            }
            total += dividendToClaim; // no overflow
        }
        return total; // total is in uint128 range (capped by uint128 dividendToken.totalDividendAmount)
    }

    /////////////////////////////////////
    // Getter Methods

    /// @notice The number of dividend token types(contract addresses) disbursed at least one or more times
    /// @dev After calling `getDividendTokenCount`, contract addresses can be retrieved by `getDividendTokenAddressAtIndex`
    /// @return the dividend token type(contract address) count
    function getDividendTokenCount() constant returns (uint256) {
        return dividendTokenList.length;
    }

    /// @notice Retrieve the dividend token contract address
    /// @dev first address : getDividendTokenAddressAtIndex(0), last address : getDividendTokenAddressAtIndex(getDividendTokenCount()-1)
    /// @param _index Array index starting from 0
    /// @return ERC20/ERC223 dividend token contract address
    function getDividendTokenAddressAtIndex(uint _index) constant returns (address) {
        return dividendTokenList[_index];
    }

    /// @notice Retrieve dividend token status data of `_dividendToken` type
    /// @param _dividendToken ERC20/ERC223 dividend token contract address
    /// @return totalDividendTokenAmount Total dividend token amount
    /// @return totalClaimedDividendTokenAmount Total claimed dividend token amount
    /// @return lastDeactivatedDividendIndex last deactivated dividend disbursement index (index value starts from 1)
    function getDividendTokenStatus(address _dividendToken) constant
        returns (uint256 totalDividendTokenAmount, uint256 totalClaimedDividendTokenAmount, uint256 lastDeactivatedDividendIndex) {

        DividendToken storage dividendToken = dividendTokens[_dividendToken];
        totalDividendTokenAmount = uint256(dividendToken.totalDividendAmount);
        totalClaimedDividendTokenAmount = uint256(dividendToken.totalClaimedDividendAmount);
        lastDeactivatedDividendIndex = uint256(dividendToken.lastDeactivatedDividendIndex);
    }

    /// @notice Retrieve dividend token claim status data of `_tokenHolder` account for `_dividendToken` type
    /// @param _dividendToken ERC20/ERC223 dividend token contract address
    /// @param _tokenHolder Token holder account address
    /// @return claimedDividendTokenAmount The claimed dividend token(`_dividendToken` type) amount of `_tokenHolder` account
    /// @return unclaimedDividendDisbursementCount The unclaimed dividend disbursement count of `_tokenHolder` account for `_dividendToken` type
    function getDividendClaimStatus(address _dividendToken, address _tokenHolder) constant
        returns (uint256 claimedDividendTokenAmount, uint256 unclaimedDividendDisbursementCount) {

        DividendToken storage dividendToken = dividendTokens[_dividendToken];
        DividendClaimStatus storage claimStatus = dividendToken.dividendClaims[_tokenHolder];
        claimedDividendTokenAmount = uint256(claimStatus.claimedDividendAmount);
        uint startIdx = claimStatus.nextDividendIndexToClaim;
        if (startIdx < dividendToken.lastDeactivatedDividendIndex) {
            // skip the deactivated dividend disbursements
            // `lastDeactivatedDividendIndex` index number starts from 1 (1 : indicating `dividendToken.dividendDisbursementHistory[0]`)
            startIdx = dividendToken.lastDeactivatedDividendIndex;
        }
        unclaimedDividendDisbursementCount = dividendToken.dividendDisbursementHistory.length - startIdx;
    }

    /// @notice Calculate the unclaimed dividend token amount of `_tokenHolder` account not including the portion for the deactivated dividend disbursements
    /// @dev Because this function could cause gas limit exception while for-looping in `accumulateDividendTokenAmountToClaim`,
    ///    this function is separated from `getDividendClaimStatus`
    /// @param _dividendToken ERC20/ERC223 dividend token contract address
    /// @param _tokenHolder Token holder account address
    /// @return the accumulated amount of claimable dividend token amount
    function getUnclaimedDividendTokenAmount(address _dividendToken, address _tokenHolder) constant returns (uint256) {
        DividendToken storage dividendToken = dividendTokens[_dividendToken];
        DividendClaimStatus storage claimStatus = dividendToken.dividendClaims[_tokenHolder];
        uint startIdx = claimStatus.nextDividendIndexToClaim;
        if (startIdx < dividendToken.lastDeactivatedDividendIndex) {
            // skip the deactivated dividend disbursements
            // `lastDeactivatedDividendIndex` index number starts from 1 (1 : indicating `dividendToken.dividendDisbursementHistory[0]`)
            startIdx = dividendToken.lastDeactivatedDividendIndex;
        }
        uint endIdx = dividendToken.dividendDisbursementHistory.length;
        if (startIdx >= endIdx) { return 0; }
        return accumulateDividendTokenAmountToClaim(dividendToken, startIdx, endIdx, false /*readonly*/);
    }

    /////////////////////////////////////
    // Modifiers

    modifier only(address x) {
        assert(msg.sender == x);
        _;
    }

    modifier non_zero_address(address x) {
        assert(x != 0);
        _;
    }

    /////////////////////////////////////
    // Safe Math Methods

    function add128(uint128 x, uint128 y) constant internal returns (uint128 z) {
        assert((z = x + y) >= x);
    }
}