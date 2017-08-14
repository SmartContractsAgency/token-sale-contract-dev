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
    generated and assigned to the ASXTokenSale contract.

    The ASXTokenSale distribution model is purposefully flexible to allow multiple
    rounds at different discrete times with a variable percentage of the total ASX
    tokens available for distribution in each round. There are 3 rounds in total.

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

    Once all contribution rounds are completed the ASXTokenSale contract will cede its
    ArtstockExchangeToken controller position to the 0X0 address.
*/

/**
* @title - Artstock Exchange token sale contract
* @author - Terry Wilkinson [terryw@artstockx.com]
* @dev - inherits from DSMath (https://github.com/dapphub/ds-math)
* @dev - DSMath is a safe math lib with WAD division/multiplication handling and min/max. WAD
    calculations require uint128.We have updated the the basic safe math function names to be
    compatible with solc 0.4.13 compilation
*/
contract ASXTokenSale is Ownable, DSMath, TokenController{
    /* contract init vars and log */
    ArtstockExchangeToken public ASX;           // the ASX token
    uint public initSupply;                     // the initial/total supply fo ASX (S)
    address public postSaleController;          // the contract which will be controller for the ArtstockExchangeToken contract after the sale (the postSale controller will enforce the locking period and circuit breakers)
    uint128 public initMinTarget;               // the initial minimum market cap of the total ASX supply (Imin)
    uint128 public initMaxTarget;               // the initial maximum market cap of the total ASX supply (Imax)
    uint128 public basePercentage;              // the base token distribution percentage (a)
    uint128 public perRoundPercentage;          // additional token distribution percentage per round (b)
    uint128 public thresholdCoefficient;        // the % change in threshold size from one round to the next (t)
    uint128 public capCoefficient;              // the % of change in maximum contribution cap size from one round to the next (m)
    bool initialized;                           // ASXTokenSale contract initialization flag

    event Init(uint _initMinTarget, uint _initMaxTarget, uint _basePercentage, uint _perRoundPercentage, uint _thresholdCoefficient, uint _capCoefficient); // ASXToken contract initialization log event

    /* contribution round vars and logs */
    uint roundCount;                         // track the current round count, max count 3, but rounds are indexed 0-2, (R)

    /**
    * @dev - Round is a structure that attaches contribution round information to a given round number
    */
    struct Round {
        uint128 start;                          // start block of each round
        uint128 end;                            // end block of each round
        uint128 avail;                          // the maximum allocation of ASX for distribution in the current round (A)
        uint128 threshold;                      // the contribution threshold each round (T)
        uint128 cap;                            // the contribution cap each round (M)
        uint128 price;                          // the price of ASX/ETH for each round, (P)
        uint128 dist;                           // the final distribution amount of ASX for each round (D)
        uint128 totalContrib;                   // the total contributions for each round (C)
        bool initialized;                       // initialization flag for each round
        bool ended;                             // end flag for each round
        mapping (address => uint128) contrib;   // the total contributed amount for each address in each round
        mapping (address => uint128) claimed;   // amount of rewards that have been claimed by an address in each round (0 or the total amount)
    }

    mapping (uint => Round) public rounds;   // map round number to round information


    event RoundInit(uint _roundIndex, uint _roundStart, uint _roundEnd, uint _allocation, uint _threshold, uint _cap);                                                    // round initialization log event
    event RoundEnd(uint _roundIndex, uint _endBlock, uint _finalPrice, uint _finalContributionTotal, uint _finalDistribution);          // round end log event
    event Contribution(uint _roundIndex, address _contributor, uint _amount);                                                           // contribution log event
    event Claim(uint _roundIndex, address _claimant, uint _amount);                                                                     // claiming log event
    event SaleEnd(uint _saleEndBlock, uint _totalSaleContributions, uint _totalSaleDistribution);                                       // sale end log event
    event CollectFunds(uint amountETH, uint _amountASX);                                                                                // collect funds log event

    /**
    * @dev - ArtStockSale constructor
    * @param _initSupply - the initial/total supply of tokens to be minted by the ArtstockExchangeToken contract during the ASXTokenSale contract initialization
    */
    function ASXTokenSale(uint _initSupply, address _postSaleController) {
        require(_initSupply <= 10**38);                 // _initSupply will never exceed 10**38, this ensures safe compatibility with DSMath WAD operations
        require(_postSaleController != address(0x0));   // _postSaleController cannot be the 0x0 address
        initSupply = _initSupply;                       // set public storage variable initSupply
        postSaleController = _postSaleController;       // set the post sale controller storage var
    }

    /**
    * @dev - initialize function for creating the ASX token supply and setting the contribution model initial parameters
    * @param _asx - the ASX Token contract object
    * @param _initMinTarget - the initial range minimum target
    * @param _initMaxTarget - the initial range maximum target
    * @param _basePercentage - the base token distribution percentage in WAD format (so something less than 10**18)
    * @param _perRoundPercentage - additional token distribution percentage per round in WAD format (less than 10**18)
    * @param _thresholdCoefficient - used to calculate the % change in threshold size from one round to the next in WAD format (10**18 is 100%)
    * @param _capCoefficient - used to calculate the % change in maximum contribution cap size from one round to the next in WAD format
    * @return bool - success after successfully completing the initialization
    */
    function initialize(
        ArtstockExchangeToken _asx,
        uint _initMinTarget,
        uint _initMaxTarget,
        uint _basePercentage,
        uint _perRoundPercentage,
        uint _thresholdCoefficient,
        uint _capCoefficient

    ) onlyOwner returns (bool success) {
        assert(address(ASX) == address(0));                                             // assert that the ASX token holding variable is empty
        require(address(_asx.controller) == address(this));                             // require that the ArtStockSale contract is the controller of the ASX token contract
        require(_asx.totalSupply() == 0);                                               // require that the ASX token totalSupply is 0
        require(_initMinTarget > 0);                                                    // require the min initial target is greater than 0
        require(_initMaxTarget > _initMinTarget && _initMaxTarget < 10**26);            // require the max initial target is greater than the min target but less than the total current actual ETH supply (~ 100M ETH) decimal places
        require(0 < _basePercentage && _basePercentage < 10**18);                       // require that the base percentage is greater than 0 and less than 19 decimal places (10**18 = 100% for WAD calculations)
        require(0 < _perRoundPercentage && _perRoundPercentage < 10**18);               // require that round percentage is greater than 0 and  less than 19 decimal places (10**18 = 100% for WAD calculations)
        require(_thresholdCoefficient >= 10**18 && _thresholdCoefficient < 10**19);     // require that the threshold coefficient is never above 1000% (it will be much lower than this)
        require(_capCoefficient > _thresholdCoefficient && _capCoefficient < 10**19);   // require the cap coefficient is greater than the threshold coefficient and less than 1000% (it will be much lower than this)

        ASX = _asx;                                                                     // set the ASX contract variable to the ASX token contract
        ASX.generateTokens(address(this),initSupply);                                   // create ASX equal to initSupply and assign them to the ArtStockSale contract address

        /**
        * @dev -  the following are cast to uint128 for DSMath compatibility. uint128 allows
          for 39 decimal positions (at ~ 3.4e+38). The above 'requires' will prevent any overflow
          possibility for uint128 types
        */
        initMinTarget = cast(_initMinTarget);                                           // setting initial storage variables
        initMaxTarget = cast(_initMaxTarget);                                           //
        basePercentage = cast(_basePercentage);                                         //
        perRoundPercentage = cast(_perRoundPercentage);                                 //
        thresholdCoefficient = cast(_thresholdCoefficient);                             //
        capCoefficient = cast(_capCoefficient);                                         //
        initialized = true;                                                             // set the initialized variable to true, preventing any future initializations

        Init(_initMinTarget, _initMaxTarget, _basePercentage, _perRoundPercentage, _thresholdCoefficient, _capCoefficient); // log the ArtStockFund initialize event
        return true;                                                                    // return success
    }

    /**
    * @dev - fallback function, any ETH paid is contributed to the current active round, or reverted if no round is active
    */
    function () payable {
        contribute();   // fallback to contribution
    }

    /**
    * @dev - initialization function for setting the parameters, start block, and end block of each contribution round
    * @param _roundStart - the start block of the contribution round
    * @param _roundEnd - the end block of the contribution round
    * @return success - true after successfully completing the initialization
    */
    function initializeRound( uint _roundStart, uint _roundEnd) onlyOwner returns (bool success) {
        assert(initialized == true);                                        // assert that the ASXTokenSale contract has already been initialized (only relevant for Round 0)
        assert(roundCount < 3);                                             // assert that the maximum number of initialized rounds is 3. roundCount iteration happens at the end of initialization, so roundCount 3 would actually be initializing the 4th round
        require(_roundStart >= block.number);                               // require the round start block to be greater than (or equal to) the current block number
        require(_roundEnd > _roundStart);                                   // require the round end block to be greater than the round start block

        Round storage round = rounds[roundCount];                           // get the virtually initialized Round struct for this roundCount

        assert(round.initialized == false);                                 // assert that this round has not already been initialized

        uint currentRnd = currentRound();

        if(roundCount > 0){                                                 // for all rounds beyond Round 0, check that there is no possible round overlap
            Round storage prevRound = rounds[currentRnd];                   // iteration happens at the end of initialization, so currentRound is proper since it == roundCount - 1 for rounds above 0
            assert(_roundStart > uint256(prevRound.end));                   // assert that the current round start block is greater than the previous round end block
        }

        round.start = cast(_roundStart);                                    // set the roundStart of the current round to the current block number
        round.end = cast(_roundEnd);                                        // set the roundEnd of the current round to currentRoundEnd

        round.avail = calcAvail();                                          // calculate the maximum available ASX for this round
        round.threshold = calcThreshold();                                  // calculate the contribution threshold for this round
        round.cap = calcCap();                                              // calculate the contribution cap for this round

        round.initialized = true;                                           // set the round initialization flag to true
        roundCount += 1;                                                    // iterate the round count
        RoundInit(currentRnd, _roundStart, _roundEnd, uint(round.avail), uint(round.threshold), uint(round.cap));    // log the round initialization event
        return true;                                                        // return success
    }

    /**
    * @dev - helper function to calculate the maximum available tokens allocated for distribution in the current round
    * @return avail - the calculated available token allocation
    */
    function calcAvail() private returns (uint128 avail) {
        uint128 cumulativeRoundPercent = percentCoefficient(roundCount);            // percent coefficient for the initializing round (p)
        uint128 totalAllocation = wmul(cumulativeRoundPercent, cast(initSupply));   // calculate the maximum available ASX in R0 (A0 = p0*S)
        if (roundCount == 0) {                                                      // Round 0 case
            avail = totalAllocation;                                                // in Round 0, available amount is simply totalAllocation
            return avail;
        } else {                                                                    // cases beyond Round 0
            uint prevCount = dssub(roundCount, 1);                                  // get previous round count
            Round storage prevRound = rounds[prevCount];                            // get Round struct for previous round
            avail = wsub(totalAllocation, prevRound.dist);                          // calculate the maximum available ASX in R1/R2 (A1 = (p1*S)-D0 / A2 = (p2*S)-D1)
            return avail;
        }
    }

    /**
    * @dev - helper function to calculate the contribution threshold in the current round, the contribution threshold is the contribution point where all available tokens will be distributed
    * @return threshold - the calculated threshold amount
    */
    function calcThreshold() private returns (uint128 threshold) {
        uint128 currentRoundPercent = percentCoefficient(roundCount);           //percent coefficient for the current round (p)

        if (roundCount == 0) {
            threshold = wmul(currentRoundPercent, initMinTarget);               // round 0 threshold depends only on the the initial min target and the round percentage
            return threshold;
        } else {
            uint128 tBase = Calc(false,false,roundCount);
            uint128 cBase = Calc(false,true,roundCount);
            threshold = wmax(tBase, cBase);                                   // current threshold value is determined by whether C<T or C>=T for the previous round, take the larger of C or T
            return threshold;
        }
    }

    /**
     * @dev - helper function to calculate the contribution cap in the current round
     * @return cap - the calculated cap amount
     */
    function calcCap() private returns (uint128 cap) {
        uint128 currentRoundPercent = percentCoefficient(roundCount);           //percent coefficient for the current round (p)

        if (roundCount == 0) {
            cap = wmul(currentRoundPercent, initMaxTarget);               // round 0 threshold depends only on the the initial min target and the round percentage
            return cap;
        } else {
            uint128 tBase = Calc(true,false,roundCount);
            uint128 cBase = Calc(true,false,roundCount);
            cap = wmax(tBase, cBase);                                   // current threshold value is determined by whether C<T or C>=T for the previous round, take the larger of C or T
            return cap;
        }
    }

    /**
     * @dev - helper function to calculate the relevant amounts for calcThreshold() and calcCap()
     * @param _targetType - for choosing the relevant target, false when calculating for a threshold target, true when calculating for a cap target
     * @param _calcType - both calcThreshold() and calcCap() need to compare previous round contribution based calculations and threshold based calculations, false for previous round threshold calcs and true for previous round contrib calcs
     * @return calc - the calculated amount
     */
    function Calc(bool _targetType, bool _calcType, uint _roundCount) private returns (uint128 calc) {
        uint128 multiplier;
        uint128 calcType;
        Round storage round0 = rounds[0];
        uint128 currentRoundPercent = percentCoefficient(_roundCount);          //roundCount has not been iterated yet so it accurately represents the current round
        uint prevRnd = dssub(_roundCount, 1);
        uint128 prevRoundPercent = percentCoefficient(prevRnd);

        if(_targetType == false){
            multiplier = thresholdCoefficient;
        } else {
            multiplier = capCoefficient;
        }

        if(_roundCount == 1){
            if(_calcType == false){
                calcType = round0.threshold;
            } else {
                calcType = round0.totalContrib;
            }
            calc = wsub(wmul(currentRoundPercent, wmul(multiplier, wdiv(calcType, prevRoundPercent))), round0.totalContrib); //(p1*t*(T0/p0)))-C0
            return calc;
        } else {
            Round storage round1 = rounds[1];
            if(_calcType == false){
                calcType = round1.threshold;
            } else {
                calcType = round1.totalContrib;
            }
            calc = wsub(wsub(wmul(currentRoundPercent, wmul(multiplier, wdiv(wadd(calcType, round0.totalContrib), prevRoundPercent))), round0.totalContrib), round1.totalContrib);       //(p2*t*((C0+T1)/p1)))-C0-C1
            return calc;
        }
    }

    /**
    * @dev - helper function to get the current round count. roundCount is iterated when a round is initialized so the true index of the current round is roundCount - 1 for all rounds above 0
    * @param _roundCount - the round to check cumulative percentage for
    * @return percent - the current round cumulative percent coefficient
    */
    function percentCoefficient(uint _roundCount) private constant returns (uint128 percent) {
        percent = wadd(basePercentage, wmul(perRoundPercentage, cast(_roundCount)));   // calculate the cumulative percent coefficient
        return percent;                                                                 // return percent coefficient
    }

    /**
    * @dev - helper function to get the current round count. roundCount is iterated when a round is initialized so the true index of the current round is roundCount - 1 for all rounds above 0
    * @return index - the current round index
    */
    function currentRound() constant returns (uint index) {
        if(roundCount>0) {
            index = dssub(roundCount, 1);       // roundCounts greater than 0 have indexes of roundCount -1
            return index;                       // return the round index
        } else {
            index = roundCount;                 // roundCount 0 has an index of 0, this is before round 0 has been initialized
            return index;                       // return the round index
        }
    }

    /**
    * @dev - allows the contributor to contribute to a current active round. If no round is active transaction will be reverted
    */
    function contribute() payable returns (bool success) {
        uint currentBlock = block.number;                                                               // set the current block number
        uint currentRnd = currentRound();                                                               // get the current round index
        Round storage round = rounds[currentRnd];                                                       // get the current round info struct

        assert(currentBlock >= uint256(round.start) && currentBlock <= uint256(round.end));             // assert that the current block is between the current round start and end blocks, inclusive
        assert(msg.value >= 0.01 ether);                                                                // assert a contribution minimum of 0.01 ETH

        round.contrib[msg.sender] = wadd(round.contrib[msg.sender], cast(msg.value));                   // cast msg.value as a uint128 and add it to the msg.sender's contribution amount for this round
        round.totalContrib = wadd(round.totalContrib, cast(msg.value));                                 // add msg.value to the total contribution amount for this round
        round.price = wmax(wdiv(round.threshold, round.avail), wdiv(round.totalContrib, round.avail));  // update price, P = max(T/A, C/A)
        round.dist = wmin(wmul(round.avail, wdiv(round.totalContrib, round.threshold)), round.avail);   // update distribution, D = min(A*(C/T), A)

        if(round.totalContrib >= round.cap){                                                            // check for "round.totalContrib >= round.cap" end condition
            round.ended = true;                                                                         // set round end flag to true
            round.end = cast(currentBlock);                                                             // update round end block
            RoundEnd(currentRnd, uint(round.end), uint(round.totalContrib), uint(round.price), uint(round.dist)); // log round end event
            if(roundCount == 3){                                                                        // check for end of sale at any round end, if it is the final round ending then fire sale end
                saleEnd();
            }
        }

        Contribution(currentRnd, msg.sender, msg.value);                                                // log the contribution event
        return true;                                                                                    // return success
    }

    /**
    * @dev - overloaded contribute function to handle incoming proxyPayment calls from the ArtstockExchangeToken contract
    * @param _contributor - the address of the contributor who sent ETH to the ArtstockExchangeToken contract
    * @return true
    */
    function contribute(address _contributor) payable returns (bool success) {
        uint currentBlock = block.number;                                                               // set the current block number
        uint currentRnd = currentRound();                                                               // get the current round index
        Round storage round = rounds[currentRnd];                                                       // get the current round info struct

        assert(currentBlock >= uint256(round.start) && currentBlock <= uint256(round.end));             // assert that the current block is between the current round start block and end block, inclusive
        assert(msg.value >= 0.01 ether);                                                                // assert a contribution minimum of 0.01 ETH

        round.contrib[_contributor] = wadd(round.contrib[_contributor], cast(msg.value));               // cast msg.value as a uint128 and add it to the _contributor's contribution amount for this round
        round.totalContrib = wadd(round.totalContrib, cast(msg.value));                                 // add msg.value to the total contribution amount for this round
        round.price = wmax(wdiv(round.threshold, round.avail), wdiv(round.totalContrib, round.avail));  // update price, P = max(T/A, C/A)
        round.dist = wmin(wmul(round.avail, wdiv(round.totalContrib, round.threshold)), round.avail);   // update distribution, D = min(A*(C/T), A)

        if(round.totalContrib >= round.cap){                                                            // check for "round.totalContrib >= round.cap" end condition
            round.ended = true;                                                                         // set round end flag to true
            round.end = cast(currentBlock);                                                             // update round end block
            RoundEnd(currentRnd, uint(round.end), uint(round.totalContrib), uint(round.price), uint(round.dist));   // log round end event
            if(roundCount == 3){                                                                        // check for end of sale at any round end, if it is the final round ending then fire sale end
                saleEnd();
            }
        }

        Contribution(currentRnd, msg.sender, msg.value);                                                // log the contribution event
        return true;                                                                                    // return success
    }

    /**
    * @dev - a function for contributors to claim ASX rewards from previous rounds
    * @param _round - the round to claim ASX from
    * @return true
    */
    function claim(uint _round) returns (bool success) {
        uint currentBlock = block.number;                                       // set the current block number
        Round storage round = rounds[_round];                                   // get the _round info struct

        assert(currentBlock > uint(round.end) && uint(round.end) != 0);         // assert that the current block number is greater than the end block of the round being claimed (can only claim after a round is over),
                                                                                // and assert that the round end block is not 0 (end blocks for virtually initialized Rounds will be 0, all "non-default" rounds will have a non-zero value)

        if(round.ended == false){                                               // check for end of round updating, the first claim after the round has ended will trigger an update
            round.ended = true;                                                 // set round end flag to true
            RoundEnd(currentRound(), uint(round.end), uint(round.totalContrib), uint(round.price), uint(round.dist));   // log round end event
            if(roundCount == 3){                                                // check for end of sale at any round end, if it is the final round ending then fire sale end
                saleEnd();
            }
        }

        if (round.claimed[msg.sender] != 0 || round.totalContrib == 0) {        // check if msg.sender already claimed or there is no contribution this round
            return true;                                                        // return (not revert) because we could be iterating with claimAll
        }

        uint128 userTotal  = round.contrib[msg.sender];                         // get the contributor's total contribution amount for this round
        uint128 price = round.price;                                            // get the final price of this round
        uint128 reward = wmul(price, userTotal);                                // multiply contribution times the price to get the contributor's reward

        round.claimed[msg.sender] = reward;                                     // change claimed amount of the sender (for this round) to reward
        ASX.transfer(msg.sender, uint(reward));                                 // transfer claimed reward to the sender

        Claim(_round, msg.sender, uint(reward));                                // log the claim event
        return true;                                                            // return success
    }

    /**
    * @dev - function to iterate over each round until the current one and try to claim rewards
    */
    function claimAll() {
        for (uint i = 0; i < roundCount; i++) { // iterate over each round; roundCount is one greater than the round index so this will iterate up to the current round. Current round claims will throw if the current block is not after the round end block.
            claim(i);                           // call claim() for each iterated round
        }
    }

    /**
    * @dev - function finalize the sale which entails ceding control of the ArtstockExchangeToken contract to the post sale controlling contract
    * @return true
    */
    function saleEnd() private returns (bool success) {
        uint128 totalContributions;                                     // total contributions
        uint128 totalASXDistributed;                                    // total ASX distributed
        uint currentBlock = block.number;
        for (uint i = 0; i < roundCount; i++) {                      // iterate over each round; roundCount is one greater than the round index, so this will iterate up to the current final round.
            Round storage round = rounds[i];                            // get round i info
            totalContributions += round.totalContrib;                   // add round contributions to the total contributions
            totalASXDistributed += round.dist;                          // add the round distribution to the total distribution
        }
        SaleEnd(currentBlock, totalContributions, totalASXDistributed); // log the sale end event
        ASX.changeController(postSaleController);                       // change ArtstockExchangeToken controller to the post sale controller
        return true;
    }

    /**
    * @dev - Artstock Exchange will collect all remaining ASX and contributed ETH after the last contribution period has ended
    * @return true
    */
    function collectFunds() onlyOwner returns (bool success) {
        assert(address(ASX.controller) == postSaleController);   // assert that the postSaleController contract is the controller of the ArtstockExchangeToken contract
                                                        // ASX.controller can only be set to the postSaleController during saleEnd()
                                                        // fund collection is only available after sale finalization for two reasons:
                                                        // i) to guarantee ETH recycling is impossible during the sale period, and
                                                        // ii) to guarantee that Artstock controlled ASX tokens are always subject to the postSaleController contract locking rules

        uint asxBalance = ASX.balanceOf(address(this)); // get the remaining ASX balance of the ArtstockExchangeToken contract

        ASX.transfer(msg.sender, asxBalance);           //transfer all remaining ASX tokens to the authorized msg.sender
        msg.sender.transfer(this.balance);              // transfer all available ETH to the authorized msg.sender

        CollectFunds(this.balance, asxBalance);         // log collect funds event
        return true;                                    // return success
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
        tokens are originally controlled by the ASXTokenSale contract, and once claimed after each round should be freely
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
    * @dev - sale info getter function
    * @param _participant - the address of a sale participant (using 0x0, or a non-participant address, will simply return the general sale information)
    * @return (Round0, Round1, Round2) - returns any array for each round of the sale
    */
    function getSaleInfo(address _participant) returns (uint128[10] Round0, uint128[10] Round1, uint128[10] Round2) {

        for (uint i = 0; i < roundCount; i++) {                         // iterate over each round; roundCount is one greater than the round index, so this will iterate up to the current final round.
            Round storage round = rounds[i];                            // get round i info
            if(i == 0) {                                                // add each round info to the appropriate return array
                Round0 = [round.start, round.end, round.threshold, round.cap, round.avail, round.dist, round.price, round.totalContrib, round.contrib[_participant], round.claimed[_participant]];
            } else if (i == 1) {
                Round1 = [round.start, round.end, round.threshold, round.cap, round.avail, round.dist, round.price, round.totalContrib, round.contrib[_participant], round.claimed[_participant]];
            } else {
                Round2 = [round.start, round.end, round.threshold, round.cap, round.avail, round.dist, round.price, round.totalContrib, round.contrib[_participant], round.claimed[_participant]];
            }
        }
        return (Round0, Round1, Round2);
    }
}