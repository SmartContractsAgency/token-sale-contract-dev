var ArtstockExchangeTokenContract = artifacts.require("ArtstockExchangeToken");
var SnapshotableTokenFactoryContract = artifacts.require("SnapshotableTokenFactory");
var ASXContributionContract = artifacts.require("ASXContribution");

module.exports = function(deployer, network, accounts) {

  var snapshotableTokenFactory;
  var asxToken;
  var asxContribution;
  if (network == 'development') {
    snapshotableTokenFactory = {
      address : '0xa8e055d89579a74b0110728a740e18e80c44e211'
    };

    asxToken = {
      address : '0xaeee4b4fdfa06dc8f259b46019a1cdc7fd631001',
      dividendDisburser : '0x5677e23889387f0d0e774f2e930e91bcee9dcaa6'
    };

    asxContribution = {
      address : '0xebf70c8443a14dd13cdf4997d13ba889945d1f31',
      fundReceiverWallet: '0x0000000000000000000000000000000000000002',
      initSupply : web3.toWei('100000000','ether'),
      postContribController : '0x0000000000000000000000000000000000000001',
      initMinTarget : web3.toWei('250000','ether'), // $100M at $400/ETH
      initMaxTarget : web3.toWei('1250000','ether'), // $500M at $400/ETH
      thresholdCoefficient : web3.toWei('1.5','ether'),
      capCoefficient : web3.toWei('2','ether'),
      roundCount : '3',
      roundZero : {
        roundIndex : '0',
        startBlock : '1000',
        endBlock : '2000',
        targetPercentage : web3.toWei('0.1','ether')
      },
      roundOne : {
        roundIndex : '1',
        startBlock : '3000',
        endBlock : '4000',
        targetPercentage : web3.toWei('0.05','ether')
      },
      roundTwo : {
        roundIndex : '2',
        startBlock : '5000',
        endBlock : '6000',
        targetPercentage : web3.toWei('0.05','ether')
      }
    };
  } else if (network == "ropsten") { // ropsten testnet

    throw "error: deployment for ropsten network is not yet supported";

  } else if (network == "rinkeby") { // rinkeby testnet

    snapshotableTokenFactory = {
      // address : '0xf99ded0eec1575ca9de64b8593c2241da925aa12'
      // address : '0x342403360576ed23173f2ad3fc27e897d006ba25'
      address : '0x1a1a0f93c26253bd42156b3afefd55e56ddc9da7'
    };

    asxToken = {
      // address : '0x57396fd109ee084e50fa3a05c8e9f0a25fe66a8a',
      // address : '0xdce383e3e2f0aa384fac28671c75d9fbb3cbe137',
      address : '0xad5a397994568d2d35279d48797ed1f307188078',
      dividendDisburser : '0x5677e23889387f0d0e774f2e930e91bcee9dcaa6'
    };

    asxContribution = {
      // address : '0x2b58bb3c3c4900a536f89578c94fb7de6c5caf41',
      // address : '0xcef5a351d54a3b0cd09b16332ff0c1e735d06580',
      address : '0xf750edb6ea588279fd3e866ba30138d763d078b5',
      fundReceiverWallet: '0x5677e23889387f0d0e774f2e930e91bcee9dcaa6',
      initSupply : web3.toWei('100000000','ether'),
      postContribController : '0x0000000000000000000000000000000000000001',
      initMinTarget : web3.toWei('250','ether'),
      initMaxTarget : web3.toWei('1250','ether'),
      thresholdCoefficient : web3.toWei('1.5','ether'),
      capCoefficient : web3.toWei('2','ether'),
      roundCount : '3',
      // 1 hour : 60*(60/15) = 240 block
      // 1 day : 24*60*(60/15) = 5760 block
      roundZero : {
        roundIndex : '0',
        // startBlock : '855675', // SF 7 Sep Thursday 10PM
        // endBlock : '857595', // SF 8 Sep Friday 6AM
        startBlock : '859995', // SF 8 Sep Friday 4PM
        endBlock : '860115', // SF 8 Sep Friday 4:30AM
        targetPercentage : web3.toWei('0.1','ether')
      },
      roundOne : {
        roundIndex : '1',
        // startBlock : '858795', // SF 8 Sep Friday 11AM
        // endBlock : '859995', // SF 8 Sep Friday 4PM
        startBlock : '860175', // SF 8 Sep Friday 4:45M
        endBlock : '860295', // SF 8 Sep Friday 5:15PM
        targetPercentage : web3.toWei('0.05','ether')
      },
      roundTwo : {
        roundIndex : '2',
        // startBlock : '860235', // SF 8 Sep Friday 5PM
        // endBlock : '860475', // SF 8 Sep Friday 6PM
        startBlock : '860355', // SF 8 Sep Friday 5:30PM
        endBlock : '860475', // SF 8 Sep Friday 6PM
        targetPercentage : web3.toWei('0.05','ether')
      }
    };

  } else if (network == "live") {
    throw "error: deployment for live network is not yet supported";
  }

  console.log('Starting Contract Deployment on network ' + network);
  console.log(snapshotableTokenFactory);
  console.log(asxToken);
  console.log(asxContribution);

  var tfPromise = SnapshotableTokenFactoryContract.at(snapshotableTokenFactory.address).then(function (exiTF) {
    console.log('Found existing SnapshotableTokenFactory contract at ' + exiTF.address);
    return Promise.resolve(exiTF);
  }).catch(function (err) {
    if (err.message && err.message.includes('Cannot create instance of')) {
      console.log('Deploying new SnapshotableTokenFactory contract');
      return SnapshotableTokenFactoryContract.new().then(function (newTF) {
        console.log('Deployed new SnapshotableTokenFactory contract at ' + newTF.address);
        return newTF;
      });
    } else {
      console.error(err);
      return Promise.resolve(null);
    }
  });

  tfPromise.then(function (tf) {
    console.log('SnapshotableTokenFactory contract at ' + tf.address);

    ArtstockExchangeTokenContract.at(asxToken.address).then(function (exiT) {
      console.log('Found existing ArtstockExchangeToken contract at ' + exiT.address);
      return Promise.resolve(exiT);
    }).catch(function (err) {
      if (err.message && err.message.includes('Cannot create instance of')) {
        console.log('Deploying new ArtstockExchangeToken contract');
        return ArtstockExchangeTokenContract.new(tf.address, asxToken.dividendDisburser).then(function (newT) {
          console.log('Deployed new ArtstockExchangeToken contract at ' + newT.address);
          return newT;
        });
      } else {
        console.error(err);
        return Promise.resolve(null);
      }
    }).then(function (t) {
      console.log('ArtstockExchangeToken contract at ' + t.address);
      // t.totalSupply.call().then(function (_totalSupply) {
      //   console.log('ArtstockExchangeToken.totalSupply()=' + _totalSupply);
      // })

      ASXContributionContract.at(asxContribution.address).then(function (exiTS) {
        console.log('Found existing ASXContribution contract at ' + exiTS.address);
        return Promise.resolve(exiTS);
      }).catch(function (err) {
        if (err.message && err.message.includes('Cannot create instance of')) {
          console.log('Deploying new ASXContribution contract');
          return ASXContributionContract.new(asxContribution.initSupply, asxContribution.postContribController).then(function (newASXC) {
            console.log('Deployed new ASXContribution contract at ' + newASXC.address);
            console.log('Sending Transaction : ArtstockExchangeToken.changeController()');
            return t.changeController(newASXC.address).then(function (resCC) {
              return t.controller.call().then(function (caddr) {
                if (caddr == newASXC.address) {
                  console.log('ArtstockExchangeToken.changeController() Success!');
                  console.log('Sending Transaction : ASXContribution.initialize()');
                  return newASXC.initialize(
                      t.address, asxContribution.fundReceiverWallet, asxContribution.initMinTarget, asxContribution.initMaxTarget,
                      asxContribution.thresholdCoefficient, asxContribution.capCoefficient,
                      asxContribution.roundCount
                  ).then(function (resInit) {
                    if (resInit.logs && resInit.logs.length > 0 && resInit.logs[0].event == 'Init') {
                      console.log(resInit.logs[0]);
                      console.log('ASXContribution.initialize() Success!');
                      return newASXC.initializeRound(  // manual initialize Round 0
                          asxContribution.roundZero.roundIndex,
                          asxContribution.roundZero.startBlock,
                          asxContribution.roundZero.endBlock,
                          asxContribution.roundZero.targetPercentage
                      ).then(function (resRnd0Init) {
                        if (resRnd0Init.logs && resRnd0Init.logs.length > 0 && resRnd0Init.logs[0].event == 'RoundInit') {
                          console.log(resRnd0Init.logs[0]);
                          console.log('ASXContribution.initializeRound() for Round 0 Success!');
                          return newASXC.initializeRound(  // manual initialize Round 1
                              asxContribution.roundOne.roundIndex,
                              asxContribution.roundOne.startBlock,
                              asxContribution.roundOne.endBlock,
                              asxContribution.roundOne.targetPercentage
                          ).then(function (resRnd1Init) {
                            if (resRnd1Init.logs && resRnd1Init.logs.length > 0 && resRnd1Init.logs[0].event == 'RoundInit') {
                              console.log(resRnd1Init.logs[0]);
                              console.log('ASXContribution.initializeRound() for Round 1 Success!');
                              return newASXC.initializeRound( // manual initialize Round 2
                                  asxContribution.roundTwo.roundIndex,
                                  asxContribution.roundTwo.startBlock,
                                  asxContribution.roundTwo.endBlock,
                                  asxContribution.roundTwo.targetPercentage
                              ).then(function (resRnd2Init) {
                                if (resRnd2Init.logs && resRnd2Init.logs.length > 0 && resRnd2Init.logs[0].event == 'RoundInit') {
                                  console.log(resRnd2Init.logs[0]);
                                  console.log('ASXContribution.initializeRound() for Round 2 Success!');

                                } else {
                                  console.log(resInit);
                                  return null;
                                }
                              });
                            } else {
                              console.log(resInit);
                              return null;
                            }
                          });
                        } else {
                          console.log(resInit);
                          return null;
                        }
                      });
                    } else {
                      console.log(resInit);
                      return null;
                    }
                  });

                } else {
                  console.log('Mismatch for token controller address => ' + caddr + ' != ' + newASXC.address);
                  return Promise.resolve(null);
                }
              });
            });
          });
        } else {
          console.error(err);
          return Promise.resolve(null);
        }
      });
    });
  });
};
