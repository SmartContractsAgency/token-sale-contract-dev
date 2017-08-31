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
    uint128 public initMinTarget;               // the initial minimum market cap of the total ASX supply (Imin)
    uint128 public initMaxTarget;               // the initial maximum market cap of the total ASX supply (Imax)
    uint128 public thresholdCoefficient;        // the % change in threshold from one round to the next (t)
    uint128 public capCoefficient;              // the % of change in maximum contribution cap size from one round to the next (m)
    uint public roundCount;                     // the total number of rounds to be held
    bool initialized;                           // ASXContribution contract initialization flag

    event Init(uint _initMinTarget, uint _initMaxTarget, uint _thresholdCoefficient, uint _capCoefficient, uint _roundCount, uint[3][] _initRound); // ASXToken contract initialization log event

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


    event RoundInit(uint _roundIndex, uint _roundStart, uint _roundEnd, uint _allocation, uint _threshold, uint _cap, uint _targetPercentage);                  // round initialization log event
    event RoundEnd(uint _roundIndex, uint _endBlock, uint _finalPrice, uint _finalContributionTotal, uint _finalDistribution);          // round end log event
    event Contribution(uint _roundIndex, address _contributor, uint _amount);                                                           // contribution log event
    event Claim(uint _roundIndex, address _claimant, uint _amount);                                                                     // claiming log event
    event ContributionEnd(uint _contributionEndBlock, uint _totalContributions, uint _totalDistribution);                               // contribution period end log event
    event CollectFunds(uint amountETH, uint _amountASX);                                                                                // collect funds log event

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
    * @param _initRound - an array of initial round information for each contribution period round [start block, end block, target percentage of distribution]
    * @return success - true after successfully completing the contract initialization
    */
    function initialize(
        ArtstockExchangeToken _asx,
        uint _initMinTarget,
        uint _initMaxTarget,
        uint _thresholdCoefficient,
        uint _capCoefficient,
        uint _roundCount,
        uint[3][] _initRound

    ) onlyOwner returns (bool success) {
        assert(initialized == false);                                                   // assert that this contract has not yet been initialized for an ArtstockExchangeToken contract
        assert(address(ASX) == address(0));                                             // assert that the ASX token holding variable is empty
        require(_asx.controller() == address(this));                                    // require that the ASXContribution contract is the controller of the ASX token contract (must be set as the controller of the ArtstockExchangeToken contract before initialization here)
        require(_asx.totalSupply() == 0);                                               // require that the ASX token totalSupply is 0
        require(_initMinTarget > 0);                                                    // require the min initial target minimum is greater than 0
        require(_initMaxTarget > _initMinTarget && _initMaxTarget < 10**26);            // require the max initial target maximum is greater than the min target but less than the total current actual ETH supply decimal places (~ 100M ETH)
        require(_thresholdCoefficient >= 10**18);                                       // require the threshold coefficient is greater than(or equal to) 10**18 (WAD 100%) to ensure initial round prices start at or above previous rounds
        require(_capCoefficient >= _thresholdCoefficient && _capCoefficient < 10**19);  // require the cap coefficient is greater than(or equal to) the threshold coefficient and less than 10**19 (WAD 1000%)
        require(_initRound.length == _roundCount);                                      // require that the number of round initialization entries are equal to the number of defined rounds

        for (uint i = 0; i < _initRound.length; i++) {                                 // initialize each of the rounds with the start block, end block, and target percentage information
            initializeRound(i, _initRound[i][0], _initRound[i][1], _initRound[i][2]);
        }

        ASX = _asx;                                                                     // set the ASX contract variable to the ASX token contract
        ASX.generateTokens(address(this), initSupply);                                  // create ASX equal to initSupply and assign them to the ASXContribution contract address

        /**
        * @dev -  some of the following are cast to uint128 for DSMath compatibility. uint128 allows
          for 39 decimal positions (at ~ 3.4e+38). The above 'require' checks will prevent any overflow
          possibility for uint128 types
        */
        initMinTarget = cast(_initMinTarget);                                           // setting initial storage variables
        initMaxTarget = cast(_initMaxTarget);                                           //
        thresholdCoefficient = cast(_thresholdCoefficient);                             //
        capCoefficient = cast(_capCoefficient);                                         //
        roundCount = _roundCount;                                                       //
        initialized = true;                                                             // set the initialized variable to true, preventing any future initializations

        Init(_initMinTarget, _initMaxTarget, _thresholdCoefficient, _capCoefficient, _roundCount, _initRound); // log the ArtStockContribution initialize event
        success = true;                                                                 // return success
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
    function initializeRound(uint _roundIndex, uint _roundStart, uint _roundEnd, uint _roundTargetPercent) onlyOwner returns (bool success) {
        assert(initialized == true);                                        // assert that the ASXContribution contract has already been initialized
        require(_roundIndex < roundCount);                                  // assert that the maximum number of initializable rounds is roundCount. roundIndex starts at 0, roundCount is the max _roundIndex + 1
        require(_roundStart >= block.number);                               // require that the round start block is greater than (or equal to) the current block number
        require(_roundEnd > _roundStart);                                   // require that the round end block is greater than the round start block

        Round storage round = rounds[_roundIndex];                          // get the virtually initialized (or previously initialized) Round struct for this _roundIndex
        assert(round.start == 0 || round.start > cast(block.number));       // assert that the round is either previously uninitialized or not already underway
        round.percentage = cast(_roundTargetPercent);                       // set the round target percent of _roundTargetPercent (store as uint128)

        uint totalContributionPercentage;                                   // variable to represent the aggregate target percentage for the whole contribution period (including this round's newly set value)
        for (uint i = 0; i < roundCount; i++) {                             // for loop to get the aggregate contribution period target percentage amount
            totalContributionPercentage += uint(rounds[i].percentage);      // aggregate the round percentages
        }

        if (_roundIndex > 0) {                                              // for any round past index 0
            Round storage prevRound = rounds[dssub(_roundIndex,1)];         // get the previous Round struct info
            require(_roundStart > prevRound.end);                           // require that the round start block is greater than the previous round end block
        } else {                                                            // round 0 avail, threshold, and cap values can be calculated without previous round price and distribution information
            round.avail = calcAvail(_roundIndex);                           // calculate the maximum available ASX for this round
            round.threshold = calcThreshold(_roundIndex);                   // calculate the contribution threshold for this round
            round.cap = calcCap(_roundIndex);                               // calculate the contribution cap for this round
        }

        uint lastIndex = dssub(roundCount,1);                               // the last possible round index number
        if (_roundIndex < lastIndex) {                                      // for any round before the last round
            Round storage nextRound = rounds[dsadd(_roundIndex,1)];         // get the next Round struct info
            if (nextRound.start != 0) {                                     // if the next round has already been explicitly initialized (if not explicitly initialized then any end block is fine)
                require(_roundEnd < nextRound.start);                       // require that the round end block is less than the next round start block
            }
        }

        require(0 < totalContributionPercentage &&  totalContributionPercentage <= 10**18);        // require that the total target percentage to distribute in the entire contribution period is greater than 0 and less than(or equal to) 10**18 (WAD 100%)
        require(0 < _roundTargetPercent && _roundTargetPercent <= totalContributionPercentage);    // require that individual round target percentages are greater than 0 and less than (or equal to) the total target percentage

        round.start = cast(_roundStart);                                    // set the start block of the initialized round to _roundStart (store as uint128)
        round.end = cast(_roundEnd);                                        // set the end block of the current round to _roundEnd (store as uint128)

        RoundInit(_roundIndex, _roundStart, _roundEnd, uint(round.avail), uint(round.threshold), uint(round.cap), uint(round.percentage));    // log the round initialization event
        success = true;                                                     // return success
    }

    /**
    * @dev - function for finalizing a round, can be called by anyone after the round is over (will be called internally in the case where the round cap is reached)
    * @param _roundIndex - the index of the round to be finalized
    * @return success - true after successfully completing the finalization
    */
    function finalizeRound(uint _roundIndex) returns (bool success) {
        Round storage round = rounds[_roundIndex];                                                              // get the round information for the chosen index
        assert(round.totalContrib >= round.cap || round.end < cast(block.number));                              // assert that either the round cap has been reached or the round has expired

        if (block.number < round.end){                                                                          // if the round has ended early (because the cap was reached)
            round.end = cast(block.number);                                                                     // update round end block to the current block number
        }

        round.price = wmax(wdiv(round.threshold, round.avail), wdiv(round.totalContrib, round.avail));          // update final price, P = max(T/A, C/A)
        round.dist = wmin(wmul(round.avail, wdiv(round.totalContrib, round.threshold)), round.avail);           // update final distribution, D = min(A*(C/T), A)

        uint lastIndex = dssub(roundCount,1);                               // the last possible round index number
        if (_roundIndex < lastIndex) {                                      // for any round before the last round
            Round storage nextRound = rounds[dsadd(_roundIndex,1)];         // get the next Round struct info
            nextRound.avail = calcAvail(_roundIndex);                       // calculate the maximum available ASX for the next round
            nextRound.threshold = calcThreshold(_roundIndex);               // calculate the contribution threshold for the next round
            nextRound.cap = calcCap(_roundIndex);                           // calculate the contribution cap for the next round
        } else {                                                            // if it is the last round
            contributionEnd();                                              // call contributionEnd() to finalize the whole contribution period
        }

        RoundEnd(_roundIndex, uint(round.end), uint(round.totalContrib), uint(round.price), uint(round.dist));  // log round end event

        success = true;                                                                                         // return success
    }


    /**
    * @dev - helper function to calculate the initial available tokens allocated for distribution in the current round
    * @return avail - the calculated available token allocation
    */
    function calcAvail(uint _roundIndex) private returns (uint128 avail) {
        uint128 maxTargetPercent = cumulativeRoundPercent(_roundIndex);             // cumulative target percentage at _roundIndex
        avail = wmul(maxTargetPercent, cast(initSupply));                           // calculate the maximum possible available ASX in the current round
        for (uint i = 0; i < _roundIndex; i++) {                                    // for each previous round (but not the current index)
            Round storage round = rounds[i];                                        // get each past round info
            avail = wsub(avail, round.dist);                                        // subtract the the final distributed amount of past rounds from the maximum possible available
        }
    }

    /**
    * @dev - helper function to calculate the contribution threshold in the current round, the contribution threshold is the contribution point where all initially available tokens will be distributed
    * @return threshold - the calculated threshold amount
    */
    function calcThreshold(uint _roundIndex) private returns (uint128 threshold) {
        uint128 maxTargetPercent = cumulativeRoundPercent(_roundIndex);         // cumulative target percentage at _roundIndex
        Round storage round = rounds[_roundIndex];                              // current round info (round.avail is set at this point)
        if (_roundIndex == 0) {
            threshold = wmul(maxTargetPercent, initMinTarget);                  // round 0 threshold depends only on the the initial min target and the cumulative target percentage
        } else {                                                                // beyond round 0, threshold calculation requires the previous round's final price
            Round storage prevRound = rounds[dssub(_roundIndex,1)];             // get the previous round information
            uint128 initPrice = wmul(thresholdCoefficient, prevRound.price);    // calculate the new initial price by multiplying the previous round price by the thresholdCoefficient
            threshold = wmul(initPrice, round.avail);                           // current threshold value is the new initial price multiplied by the available amount of ASX
        }
    }

    /**
     * @dev - helper function to calculate the contribution cap in the current round
     * @return cap - the calculated cap amount
     */
    function calcCap(uint _roundIndex) private returns (uint128 cap) {
        uint128 maxTargetPercent = cumulativeRoundPercent(_roundIndex);         // cumulative target percentage at _roundIndex
        Round storage round = rounds[_roundIndex];                              // current round info (round.avail is set at this point)
        if (_roundIndex == 0) {
            cap = wmul(maxTargetPercent, initMaxTarget);                        // round 0 cap depends only on the the initial max target and the round percentage
        } else {                                                                // beyond round 0, cap calculation requires the previous round's final price
            Round storage prevRound = rounds[dssub(_roundIndex,1)];             // get the previous round information
            uint128 maxPrice = wmul(capCoefficient, prevRound.price);           // calculate the current round max price by multiplying the previous round price by the capCoefficient
            cap = wmul(maxPrice, round.avail);                                  // current cap value is the current round max price multiplied by the available amount of ASX
        }
    }

    /**
    * @dev - helper function to get the current cumulative target percentage for all rounds up to this point
    * @param _roundIndex - the round index to check cumulative percentage for
    * @return percent - the cumulative target percentage up to (and including) _roundIndex
    */
    function cumulativeRoundPercent(uint _roundIndex) private constant returns (uint128 percent) {
        for (uint i = 0; i <= _roundIndex; i++) {                               // for each previous round add the target percent amount to the total
            Round storage round = rounds[i];                                    // get each round info
            percent = wadd(percent, round.percentage);                          // add the round target percentage to the total amount
        }
    }

    /**
    * @dev - public function to allow contribution to a current active round. If no round is active transaction will be reverted
    */
    function contribute() payable returns (bool success) {
        return contribute(msg.sender);          // return private contribute call success
    }

    /**
    * @dev - private contribute function to handle all incoming contribution sources: incoming proxyPayment calls from the ArtstockExchangeToken contract, the ASXContribution contract fallback, and the normal ASXContribution.contribute() call
    * @param _contributor - the address of the contributor who sent ETH for contribution
    * @return true
    */
    function contribute(address _contributor) private returns (bool success) {
        uint roundIndex = getIndex(block.number);                                                       // get the current round index (if there is an active round, otherwise revert)
        Round storage round = rounds[roundIndex];                                                       // get the current round info struct

        assert(msg.value >= 0.01 ether);                                                                // assert a contribution minimum of 0.01 ETH

        round.contrib[_contributor] = wadd(round.contrib[_contributor], cast(msg.value));               // cast msg.value as a uint128 and add it to the _contributor's contribution amount for this round
        round.totalContrib = wadd(round.totalContrib, cast(msg.value));                                 // add msg.value to the total contribution amount for this round

        if(round.totalContrib >= round.cap){                                                            // check for "round.totalContrib >= round.cap" end condition
            finalizeRound(roundIndex);                                                                  // if this condition is met then finalize the round
        }

        Contribution(roundIndex, msg.sender, msg.value);                                                // log the contribution event
        success = true;                                                                                 // return success
    }

    /**
     * @dev - helper function to get the index of a round; will revert if _block_number is not within the start and end blocks of a round; only called at the time of contribution
     * @param _block_number - the block.number of the contribution transaction
     * @return index
     */
    function getIndex(uint _block_number) private returns (uint index) {
        bool in_round;
        for (uint i = 0; i < roundCount; i++) {
            Round storage round = rounds[i];                                                // get each round info struct
            if (_block_number >= uint(round.start) && _block_number <= uint(round.end)) {   // check if _block_number is within the block constraints of round i (it can only match one round ever)
                in_round = true;                                                            // if found in a round then set in_round to true
                index = i;                                                                  // and set index to i
            }
        }
        assert(in_round = true);                                                            // assert that _block_number was in fact within some round constraints, if not revert
    }

    /**
    * @dev - a function for contributors to claim ASX rewards from previous rounds
    * @param _roundIndex - the round to claim ASX from
    * @return true
    */
    function claim(uint _roundIndex) returns (bool success) {
        Round storage round = rounds[_roundIndex];                              // get the _round info struct

        if (round.claimed[msg.sender] != 0 || round.totalContrib == 0 || round.price == 0) { // check if msg.sender already claimed (any non-zero amount means a user has claimed); or price == 0 (this is only true when the round has not been finalized); or there is no contribution this round (any round not run yet will have 0 contribution)
            return true;                                                        // hard return (not revert) because we could be iterating with claimAll
        }

        uint128 reward = wdiv(round.contrib[msg.sender], round.price);          // divide the user's total round contribution by the final round price to get the user's contribution reward

        round.claimed[msg.sender] = reward;                                     // change claimed amount of the sender (for this round) to the amount of the reward
        ASX.transfer(msg.sender, uint(reward));                                 // transfer claimed reward to the sender

        Claim(_roundIndex, msg.sender, uint(reward));                           // log the claim event
        success = true;                                                         // return success
    }

    /**
    * @dev - function to iterate over each round to claim rewards
    */
    function claimAll() {
        for (uint i = 0; i < roundCount; i++) { // iterate over each round; roundCount is one greater than the round index so this will iterate over all rounds.
            claim(i);                           // call claim() for each incremented round
        }
    }

    /**
    * @dev - function finalize the contribution period which entails ceding control of the ArtstockExchangeToken contract to the post contribution controlling contract
    * @return true
    */
    function contributionEnd() private returns (bool success) {
        uint128 totalContributions;                                             // total contributions
        uint128 totalASXDistributed;                                            // total ASX distributed

        for (uint i = 0; i < roundCount; i++) {                                 // iterate over each round; roundCount is one greater than the round index, so this will iterate up to the current final round.
            Round storage round = rounds[i];                                    // get round i info
            totalContributions += round.totalContrib;                           // add round contributions to the total contributions
            totalASXDistributed += round.dist;                                  // add the round distribution to the total distribution
        }
        ContributionEnd(block.number, totalContributions, totalASXDistributed); // log the contribution end event
        ASX.changeController(postContribController);                            // change ArtstockExchangeToken controller to the post contribution controller
        success = true;                                                         // return success
    }

    /**
    * @dev - Artstock Exchange will collect all remaining ASX and contributed ETH after the last contribution period has ended
    * @return true - success after funds have been collected
    */
    function collectFunds() onlyOwner returns (bool success) {
        uint lastIndex = dssub(roundCount,1);                       // the last round index
        Round storage lastRound = rounds[lastIndex];                // get the last round info
        assert(block.number > lastRound.end);                       // assert that fund collection is only available after contribution period finalization; this is so for two reasons:
                                                                    // i) to guarantee ETH recycling is impossible during the contribution period, and
                                                                    // ii) to guarantee that Artstock controlled ASX tokens are always subject to the postContribController contract vesting rules

        uint asxBalance = ASX.balanceOf(address(this));             // get the remaining ASX balance of the ASXContribution contract

        ASX.transfer(msg.sender, asxBalance);                       // transfer all remaining ASX tokens to the authorized msg.sender
        msg.sender.transfer(this.balance);                          // transfer all available ETH to the authorized msg.sender

        CollectFunds(this.balance, asxBalance);                     // log collect funds event
        success = true;                                             // return success
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
    function getContributionInfo(address _participant) constant returns (uint[11][]) {
        uint[11][] memory roundInfo = new uint[11][](roundCount);
        for (uint i = 0; i < roundCount; i++) {                         // iterate over each round
            Round storage round = rounds[i];                            // get round i info
            roundInfo[i] = [uint(round.start), uint(round.end), uint(round.threshold), uint(round.cap), uint(round.percentage), uint(round.avail), uint(round.dist), uint(round.price), uint(round.totalContrib), uint(round.contrib[_participant]), uint(round.claimed[_participant])];   // add each round's info to the return array
        }
        return roundInfo;
    }
}