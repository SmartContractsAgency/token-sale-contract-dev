pragma solidity ^0.4.13;

import "./Ownable.sol";     // import OpenZepplin Ownable
import "./DSMath.sol";      // import DSMath for WAD multiplication/division and min/max
import "./ArtstockExchangeToken.sol";    // import the ASXToken contract for interaction

/**
* @license -
    Copyright 2017, Terry Wilkinson, ARTSTOCK EXCHANGE Inc.

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

* @description -
    Upon initialization of this contract, the total supply of ASX tokens will be
    generated and assigned to the ASXContribution contract.

    The ASXContribution distribution model is purposefully flexible to allow multiple
    rounds at different discrete times with a variable percentage of the total ASX
    tokens available for distribution in each round.

    The rounds are structured to guarantee that the starting price per ASX in
    subsequent rounds is always greater than the round before.

    Each round has a threshold(T) and a maximum cap(M). The maximum cap is the
    maximum total amount of contributions(C) accepted in that round. The threshold
    is the point at which all available tokens in that round(A) are fully distributed.

    If the round ends with a total contribution amount less than its threshold
    (C<T), then a proportionally less amount of tokens are distributed(D =(C/T)*A). Any
    undistributed tokens carry over to the next contribution round.

    If a round ends with a total contribution amount greater than, or equal to,
    the round threshold (C>=T), then all available tokens are distributed(D = A).

    This results in a pricing structure whereby a base price per ASX (P = T/A) remains
    constant as long as the total amount of contributions are less than
    the threshold. On the other hand, if total contributions exceed(or are equal to) the
    threshold (C>=T), then the ending price per token increases accordingly (P = C/A).

    After a round has finished, contributors can use the 'claim' or 'claimAll' functions to retrieve
    their ASX rewards based on the final price P and their contribution amount in each round.

    Once all contribution rounds are completed the ASXContribution contract will cede its
    ArtstockExchangeToken controller position to the postContribController address.
*/

/**
* @title - Artstock Exchange token contribution contract
* @author - Terry Wilkinson [terryw@artstockx.com]
* @dev - inherits from DSMath (https://github.com/dapphub/ds-math)
* @dev - DSMath is a safe math lib with WAD division/multiplication handling and min/max. WAD
    calculations require uint128. We have updated the the basic safe math function names to be
    compatible with solc 0.4.13 compilation
*/
contract ASXContribution is Ownable, DSMath, TokenController{
    /* contract init vars and log */
    ArtstockExchangeToken public ASX;           // the ASX token
    uint public initSupply;                     // the initial/total supply fo ASX (S)
    address public postContribController;       // the contract which will be controller for the ArtstockExchangeToken contract after the contribution period (the postContrib controller will enforce the company holdings vesting period and circuit breakers)
    address public fundReceiverWallet;          // the multisig wallet contract to gather and control contract ETH/ASX funds after the contribution period is finalized
    uint128 public initMinTarget;               // the initial minimum market cap of the total ASX supply (Imin)
    uint128 public initMaxTarget;               // the initial maximum market cap of the total ASX supply (Imax)
    uint128 public thresholdCoefficient;        // the % change in threshold from one round to the next (t)
    uint128 public capCoefficient;              // the % of change in maximum contribution cap size from one round to the next (m)
    uint public roundCount;                     // the total number of rounds to be held
    uint public roundIndex;                     // the index of the current contribution round
    uint128 public totalDistribution;           // tracks the current total amount of ASX distributed up until roundIndex
    uint128 public totalContribution;           // tracks the current total amount of ETH contribution up until roundIndex
    uint128 public totalPercentage;             // tracks the current cumulative target percentage of ASX distribution
    bool initialized;                           // ASXContribution contract initialization flag

    event Init(address _fundReceiverWallet, uint _initSupply, uint _initMinTarget, uint _initMaxTarget, uint _thresholdCoefficient, uint _capCoefficient, uint _roundCount); // ASXToken contract initialization log event

    /* contribution round vars and logs */

    /**
    * @dev - Round is a structure that attaches contribution round information to a given round number
    */
    struct Round {
        uint128 start;                          // start block of each round
        uint128 end;                            // end block of each round
        uint128 percentage;                     // the target distribution percentage of each round
        uint128 avail;                          // the maximum allocation of ASX for distribution in the current round (A)
        uint128 threshold;                      // the contribution threshold each round (T)
        uint128 cap;                            // the contribution cap each round (M)
        uint128 price;                          // the price of ASX/ETH for each round, (P)
        uint128 dist;                           // the final distribution amount of ASX for each round (D)
        uint128 totalContrib;                   // the total contributions for each round (C)
        mapping (address => uint128) contrib;   // the total contributed amount for each address in each round
        mapping (address => uint128) claimed;   // amount of rewards that have been claimed by an address in each round (0 or the total amount)
    }

    mapping (uint => Round) public rounds;   // map round number to round information


    event RoundInit(uint _roundIndex, uint _roundStart, uint _roundEnd, uint _targetPercentage, uint _allocation, uint _threshold, uint _cap);                  // round initialization log event
    event RoundEnd(uint _roundIndex, uint _endBlock, uint _finalPrice, uint _finalContributionTotal, uint _finalDistribution);          // round end log event
    event Contribution(uint _roundIndex, address _contributor, uint _amount);                                                           // contribution log event
    event Claim(uint _roundIndex, address _claimant, uint _amount);                                                                     // claiming log event
    event ContributionEnd(uint _contributionEndBlock, uint _totalContribution, uint _totalDistribution);                                // contribution period end log event
    event CollectFunds(uint _amountETH, uint _amountASX);                                                                                // collect funds log event

    /**
    * @dev - ASXContribution constructor
    * @param _initSupply - the initial/total supply of tokens to be minted by the ArtstockExchangeToken contract during the ASXContribution contract initialization
    */
    function ASXContribution(uint _initSupply, address _postContribController) {
        require(_initSupply <= 10**38);                 // _initSupply will never exceed 10**38, this ensures safe compatibility with DSMath WAD operations
        require(_postContribController != address(0x0));// _postContribController cannot be the 0x0 address
        initSupply = _initSupply;                       // set public storage variable initSupply
        postContribController = _postContribController; // set the post contribution controller storage var
    }

    /**
    * @dev - initialize function for creating the ASX token supply and setting the contribution model initial parameters
    * @param _asx - the ASX Token contract object
    * @param _initMinTarget - the initial range minimum target
    * @param _initMaxTarget - the initial range maximum target
    * @param _thresholdCoefficient - used to calculate the % change in threshold from one round to the next, WAD formatted (10**18 is 100%)
    * @param _capCoefficient - used to calculate the % change in maximum contribution cap size from one round to the next in WAD format
    * @param _roundCount - the total number of rounds to be run over the whole contribution period
    * @return success - true after successfully completing the contract initialization
    */
    function initialize(
        ArtstockExchangeToken _asx,
        address _fundReceiverWallet,
        uint _initMinTarget,
        uint _initMaxTarget,
        uint _thresholdCoefficient,
        uint _capCoefficient,
        uint _roundCount

    ) onlyOwner {
        assert(initialized == false);                                                   // assert that this contract has not yet been initialized for an ArtstockExchangeToken contract
        assert(address(ASX) == address(0));                                             // assert that the ASX token holding variable is empty
        require(_fundReceiverWallet != address(0x0));                                   // _fundReceiverWallet cannot be the 0x0 address
        require(_asx.controller() == address(this));                                    // require that the ASXContribution contract is the controller of the ASX token contract (must be set as the controller of the ArtstockExchangeToken contract before initialization here)
        require(_asx.totalSupply() == 0);                                               // require that the ASX token totalSupply is 0
        require(_initMinTarget > 0);                                                    // require the min initial target minimum is greater than 0
        require(_initMaxTarget > _initMinTarget && _initMaxTarget < 10**26);            // require the max initial target maximum is greater than the min target but less than the total current actual ETH supply decimal places (~ 100M ETH)
        require(_thresholdCoefficient >= 10**18);                                       // require the threshold coefficient is greater than(or equal to) 10**18 (WAD 100%) to ensure initial round prices start at or above previous rounds
        require(_capCoefficient >= _thresholdCoefficient && _capCoefficient < 10**19);  // require the cap coefficient is greater than(or equal to) the threshold coefficient and less than 10**19 (WAD 1000%)

        ASX = _asx;                                                                     // set the ASX contract variable to the ASX token contract
        ASX.generateTokens(address(this), initSupply);                                  // create ASX equal to initSupply and assign them to the ASXContribution contract address

        /**
        * @dev -  some of the following are cast to uint128 for DSMath compatibility. uint128 allows
          for 39 decimal positions (at ~ 3.4e+38). The above 'require' checks will prevent any overflow
          possibility for uint128 types
        */
        fundReceiverWallet = _fundReceiverWallet;                                       // setting initial storage variables
        initMinTarget = cast(_initMinTarget);                                           //
        initMaxTarget = cast(_initMaxTarget);                                           //
        thresholdCoefficient = cast(_thresholdCoefficient);                             //
        capCoefficient = cast(_capCoefficient);                                         //
        roundCount = _roundCount;                                                       //
        initialized = true;                                                             // set the initialized variable to true, preventing any future initializations

        Init(fundReceiverWallet, initSupply, _initMinTarget, _initMaxTarget, _thresholdCoefficient, _capCoefficient, _roundCount); // log the ArtStockContribution initialize event
    }

    /**
    * @dev - fallback function, any ETH paid is contributed to the current active round, or reverted if no round is active
    */
    function () payable {
        contribute(msg.sender);   // fallback to contribution
    }

    /**
    * @dev - initialization function for setting the parameters, start block, and end block of each contribution round, these can be amended as long as the round has started
    * @param _roundIndex - the round to initialize
    * @param _roundStart - the start block of the contribution round
    * @param _roundEnd - the end block of the contribution round
    * @param _roundTargetPercent - the target distribution percentage of the contribution round
    * @return success - true after successfully completing the round initialization
    */
    function initializeRound(uint _roundIndex, uint _roundStart, uint _roundEnd, uint _roundTargetPercent) onlyOwner {
        assert(initialized == true);                                        // assert that the ASXContribution contract has already been initialized
        require(_roundIndex < roundCount);                                  // require that the maximum number of initializable rounds is roundCount. _roundIndex starts at 0, roundCount is the max _roundIndex + 1
        require(_roundStart >= block.number);                               // require that the round start block is greater than (or equal to) the current block number
        require(_roundEnd > _roundStart);                                   // require that the round end block is greater than the round start block

        Round storage round = rounds[_roundIndex];                          // get the virtually initialized (or previously initialized) Round struct for this _roundIndex
        assert(round.start == 0 || round.start > cast(block.number));       // assert that the round is either previously uninitialized or not already underway
        round.percentage = cast(_roundTargetPercent);                       // set the round target percent of _roundTargetPercent (store as uint128)

        uint totalContributionPeriodPercentage;                             // variable to represent the aggregate target percentage for the whole contribution period (including this round's newly set value)
        for (uint i = 0; i < roundCount; i++) {                             // for loop to get the aggregate contribution period target percentage amount
            totalContributionPeriodPercentage = dsadd(totalContributionPeriodPercentage, uint(rounds[i].percentage)); // aggregate the round percentages for the whole contribution period
        }
        require(0 < totalContributionPeriodPercentage &&  totalContributionPeriodPercentage <= 10**18);  // require that the total target percentage to distribute in the entire contribution period is greater than 0 and less than(or equal to) 10**18 (WAD 100%)
        require(0 < _roundTargetPercent && _roundTargetPercent <= totalContributionPeriodPercentage);    // require that individual round target percentages are greater than 0 and less than (or equal to) the total target percentage

        if (_roundIndex > 0) {                                              // for any round past index 0
            Round storage prevRound = rounds[dssub(_roundIndex,1)];         // get the previous Round struct info
            assert(prevRound.end != 0);                                     // assert that the previous round has been initialized (i.e., a non-zero end block has been assigned) before the current round can be initialized
            require(_roundStart > prevRound.end);                           // require that the round start block is greater than the previous round end block

            if (_roundIndex == roundIndex && prevRound.price != 0) {        // if prevRound has been finalized (price != 0) and the _roundIndex is the current roundIndex
                round.avail = wsub(wmul(wadd(totalPercentage, round.percentage), cast(initSupply)), totalDistribution); // must update round.avail in case _roundTargetPercent may have changed after finalization of the last round (_roundTargetPercent affects round.avail via round.percentage)
                nextRound.threshold = wmul(wmul(thresholdCoefficient, prevRound.price), round.avail);  // similarly re-calculate the contribution threshold for this round based on prevRound.price and any change to round.avail
                nextRound.cap = wmul(wmul(capCoefficient, prevRound.price), round.avail);              // re-calculate calculate the contribution cap for this round based on prevRound.price and any change to round.avail
            }

        } else {                                                            // round 0 avail, threshold, and cap values can be calculated without previous round price and distribution information
            round.avail = wmul(round.percentage, cast(initSupply));         // calculate the maximum available ASX for round 0
            round.threshold = wmul(round.percentage, initMinTarget);        // calculate the contribution threshold for this round
            round.cap = wmul(round.percentage, initMaxTarget);              // calculate the contribution cap for this round
        }

        uint lastIndex = dssub(roundCount,1);                               // the last possible round index number
        if (_roundIndex < lastIndex) {                                      // for any round before the last round
            Round storage nextRound = rounds[dsadd(_roundIndex,1)];         // get the next Round struct info
            if (nextRound.start != 0) {                                     // if the next round has already been explicitly initialized (if not explicitly initialized then any end block is fine)
                require(_roundEnd < nextRound.start);                       // require that the round end block is less than the next round start block
            }
        }

        round.start = cast(_roundStart);                                    // set the start block of the initialized round to _roundStart (store as uint128)
        round.end = cast(_roundEnd);                                        // set the end block of the current round to _roundEnd (store as uint128)

        RoundInit(_roundIndex, uint(round.start), uint(round.end), uint(round.percentage), uint(round.avail), uint(round.threshold), uint(round.cap));    // log the round initialization event
    }

    /**
    * @dev - function for finalizing a round, can be called by anyone after the round is over (will be called internally in the case where the round cap is reached)
    * @param _roundIndex - the index of the round to be finalized
    * @return success - true after successfully completing the finalization
    */
    function finalizeRound(uint _roundIndex) public {
        require(_roundIndex == roundIndex);                                                                     // require _roundIndex to equal roundIndex (only finalize the current round)
        Round storage round = rounds[_roundIndex];                                                              // get the round information for the chosen index

        assert(round.totalContrib >= round.cap || round.end < cast(block.number));                              // assert that either the round cap has been reached or the round has expired

        if (block.number < round.end){                                                                          // if the round has ended early (because the cap was reached)
            round.end = cast(block.number);                                                                     // update round end block to the current block number
        }

        round.price = wmax(wdiv(round.threshold, round.avail), wdiv(round.totalContrib, round.avail));          // update final price, P = max(T/A, C/A)
        if (round.totalContrib < round.threshold) {                                                             // update final distribution, D = min(A*(C/T), A)
            round.dist = wdiv(round.totalContrib, round.price);
        } else {
            round.dist = round.avail;
        }

        totalContribution = wadd(totalContribution, round.totalContrib);    // add the finalized round contribution amount to the running contribution period total
        totalDistribution = wadd(totalDistribution,round.dist);             // add the finalized round distribution amount to the running distribution period total
        totalPercentage = wadd(totalPercentage, round.percentage);          // add the round target percentage to the running target percentage total amount

        uint lastIndex = dssub(roundCount,1);                               // the last possible round index number
        if (_roundIndex < lastIndex) {                                      // for any round before the last round
            uint nextIndex = dsadd(_roundIndex,1);                          // index of the next round
            Round storage nextRound = rounds[nextIndex];                    // get the next Round struct info
            if(nextRound.start != 0){                                       // be sure nextRound has been initialized to do the following calculations (because nextRound.percentage is required)
                nextRound.avail = wsub(wmul(wadd(totalPercentage, nextRound.percentage), cast(initSupply)), totalDistribution);  // calculate the maximum possible available ASX for the next round by adding totalPercentage and nextRound.percentage and multiply this sum by the intialSupply and finally subtracting the distributed tokens from previous rounds
                nextRound.threshold = wmul(wmul(thresholdCoefficient, round.price), nextRound.avail);  // calculate the contribution threshold for the next round based on the current round.price
                nextRound.cap = wmul(wmul(capCoefficient, round.price), nextRound.avail);              // calculate the contribution cap for the next round
            }
        } else {                                                            // if it is the last round
            contributionEnd();                                              // call contributionEnd() to finalize the whole contribution period
        }

        roundIndex = dsadd(roundIndex, 1);                                  // increment the round index after the current round has been finalized
        RoundEnd(_roundIndex, uint(round.end), uint(round.price), uint(round.totalContrib), uint(round.dist));  // log round end event
    }

    /**
    * @dev - public function to allow contribution to a current active round. If no round is active transaction will be reverted
    */
    function contribute() public payable {
        contribute(msg.sender);          // return private contribute call success
    }

    /**
    * @dev - private contribute function to handle all incoming contribution sources: incoming proxyPayment calls from the ArtstockExchangeToken contract, the ASXContribution contract fallback, and the normal ASXContribution.contribute() call
    * @param _contributor - the address of the contributor who sent ETH for contribution
    * @return true
    */
    function contribute(address _contributor) private {
        Round storage round = rounds[roundIndex];                                                       // get the round info for the current roundIndex
        assert(block.number >= uint(round.start) && block.number <= uint(round.end));                   // assert that the current block.number is within the block constraints of the current indexed round
        require(msg.value >= 0.01 ether);                                                               // assert a contribution minimum of 0.01 ETH
        require(round.totalContrib < round.cap);

        round.totalContrib = wadd(round.totalContrib, cast(msg.value));
        round.contrib[_contributor] += uint128(msg.value); // no overflow if totalContrib is not overflowed

        if (round.cap < round.totalContrib) {
            uint128 refund = round.totalContrib - round.cap; // no overflow
            round.contrib[_contributor] -= refund; // no overflow
            round.totalContrib = round.cap;
            msg.sender.transfer(uint256(refund)); // throw on failure
            return;
        }

        Contribution(roundIndex, _contributor, msg.value);                                              // log the contribution event
    }

    /**
    * @dev - a function for contributors to claim ASX rewards from previous rounds
    * @param _roundIndex - the round to claim ASX from
    * @return true
    */
    function claim(uint _roundIndex) public {
        Round storage round = rounds[_roundIndex];                              // get the _round info struct

        if (round.claimed[msg.sender] != 0 || round.totalContrib == 0 || round.price == 0) { // check if msg.sender already claimed (any non-zero amount means a user has claimed); or price == 0 (this is only true when the round has not been finalized); or there is no contribution this round (any round not run yet will have 0 contribution)
            return;                                                             // hard return (not revert) because we could be iterating with claimAll
        }

        uint128 reward = wdiv(round.contrib[msg.sender], round.price);          // divide the user's total round contribution by the final round price to get the user's contribution reward

        round.claimed[msg.sender] = reward;                                     // change claimed amount of the sender (for this round) to the amount of the reward
        assert(ASX.transfer(msg.sender, uint(reward)));                         // transfer claimed reward to the sender (and assert that it returns true)

        Claim(_roundIndex, msg.sender, uint(reward));                           // log the claim event
    }

    /**
    * @dev - function to iterate over each round to claim rewards
    */
    function claimAll() public {
        assert(roundIndex > 0);                             // unless roundIndex > 0, there have been no finalized rounds to claim yet
        for (uint i = 0; i < roundIndex; i++) {             // iterate over each round up to (but not including) the current roundIndex; this represents all finalized rounds
            claim(i);                                       // call claim() for each incremented round
        }
    }

    /**
    * @dev - function finalize the contribution period which entails ceding control of the ArtstockExchangeToken contract to the post contribution controlling contract
    * @return true
    */
    function contributionEnd() private {
        ASX.changeController(postContribController);                            // change ArtstockExchangeToken controller to the post contribution controller
        ContributionEnd(block.number, totalContribution, totalDistribution);    // log the contribution end event
    }

    /**
     * @dev Allows the current owner to transfer the receiving address to a different multisig receiver
     * @param _newReceiver - a new fund receiving address
     */
    function transferReceiver(address _newReceiver) onlyOwner {
        require(_newReceiver != address(0));
        fundReceiverWallet = _newReceiver;
    }

    /**
    * @dev - Artstock Exchange will collect all remaining ASX and contributed ETH after the last contribution period has ended
    * @return true - success after funds have been collected
    */
    function collectFunds() onlyOwner {
        assert(roundIndex == roundCount);                           // assert that fund collection is only available after the last round has been finalized; this is so for two reasons:
                                                                    // i) to guarantee ETH recycling is impossible during the contribution period, and
                                                                    // ii) to guarantee that Artstock controlled ASX tokens are always subject to the postContribController contract vesting rules

        uint remainingBalance = initSupply - totalDistribution;     // get the remaining non-distribution allotment of ASX in the ASXContribution contract

        assert(ASX.transfer(fundReceiverWallet, remainingBalance));  // transfer all remaining ASX tokens to the authorized fundReceiverWallet

        fundReceiverWallet.transfer(this.balance);                  // transfer all available ETH to the authorized fundReceiverWallet, (no need to assert on this, failure of a transfer will revert https://ethereum.stackexchange.com/questions/21144/assert-and-require-atomicity-while-internally-calling-another-contract)

        CollectFunds(this.balance, remainingBalance);               // log collect funds event
    }

    /**
    * @dev - called when _owner sends ether to the SnapshotableToken contract. Calls contribute, contribute will throw if there is no current active contribution round
    * @param _owner - the address that sent the ether to create tokens
    * @return true
    */
    function proxyPayment(address _owner) payable returns (bool) {
        contribute(_owner);
        return true;
    }

    /**
    * @dev - called by the ArtstockExchangeToken contract when a token transfer occurs, no need from controller for permission. All
        tokens are originally controlled by the ASXContribution contract, and once claimed after each round should be freely
        transferable
    * @param _from - the origin of the transfer
    * @param _to - the destination of the transfer
    * @param _value - the amount of the transfer
    * @return true
    */
    function onTransfer(address _from, address _to, uint _value) returns (bool) {
        return true;
    }

    /**
    * @dev - called by the ArtstockExchangeToken contract when an approve occurs, no need from controller for permission, same
        reasoning as onTransfer
    * @param _owner - the address that calls approve()
    * @param _spender - the spender in the approve() call
    * @param _value - the amount in the approve() call
    * @return true
    */
    function onApprove(address _owner, address _spender, uint _value) returns (bool) {
        return true;
    }

    /**
    * @dev - contribution info getter function
    * @param _participant - the address of a contribution participant (using 0x0, or a non-participant address, will simply return the general contribution information)
    * @return roundInfo - an array for each round of the contribution
    */
    function getContributionInfo(address _participant) public constant returns (uint[11][]) {
        uint[11][] memory roundInfo = new uint[11][](roundCount);       // empty array with entry for each round
        for (uint i = 0; i < roundCount; i++) {                         // iterate over each round of the contribution period (even those not yet finalized)
            Round storage round = rounds[i];                            // get round i info
            roundInfo[i] = [uint(round.start), uint(round.end), uint(round.threshold), uint(round.cap), uint(round.percentage), uint(round.avail), uint(round.dist), uint(round.price), uint(round.totalContrib), uint(round.contrib[_participant]), uint(round.claimed[_participant])];   // add each round's info to the return array
        }
        return roundInfo;
    }
}