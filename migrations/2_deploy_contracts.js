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
      // address : '0xf99ded0eec1575ca9de64b8593c2241da925aa12' // test 0
      // address : '0x342403360576ed23173f2ad3fc27e897d006ba25' // test 1
      // address : '0x1a1a0f93c26253bd42156b3afefd55e56ddc9da7' // test 2
      // address : '0xb918ae0fdb2811657dcde74f703005852767163a' // local test
      //address : '0xf8cfca23eca88114d7f4a598e2fd069adc3a00bf' // test 3
      address : '0x683f1097693034516391b7d8c57f17737e58dad0' // YOS test 1
    };

    asxToken = {
      // address : '0x57396fd109ee084e50fa3a05c8e9f0a25fe66a8a', // test 0
      // address : '0xdce383e3e2f0aa384fac28671c75d9fbb3cbe137', // test 1
      // address : '0xad5a397994568d2d35279d48797ed1f307188078', // test 2
      // address : '0xda87d271a0166386847d688d0dfacf29b9f8bb7b', // local test
      // address : '0x83b27d770ee4ac6b31b6f25131af6583ec92ab12', // test 3
      address : '0x859805a6bdf88265603d9ed1bd13f682a53aaff1', // YOS test 1
      dividendDisburser : '0x5677e23889387f0d0e774f2e930e91bcee9dcaa6'
    };

    asxContribution = {
      // address : '0x2b58bb3c3c4900a536f89578c94fb7de6c5caf41', // test 0
      // address : '0xcef5a351d54a3b0cd09b16332ff0c1e735d06580', // test 1
      // address : '0xf750edb6ea588279fd3e866ba30138d763d078b5', // test 2
      // address : '0xb29ff097a8d9f260b00da4798d097be8908894cf', // local test
      // address : '0xe0d5313b91d55bb123709d999c894a245ea8d1c6', // test 3
      address : '0x6d485538d3474dd79e58045b6f3a4e4001272a73', // YOS test 1
      fundReceiverWallet: '0x5677e23889387f0d0e774f2e930e91bcee9dcaa6',
      initSupply : web3.toWei('100000000','ether'),
      postContribController : '0x0000000000000000000000000000000000000001',
      initMinTarget : web3.toWei('80','ether'),
      initMaxTarget : web3.toWei('300','ether'),
      thresholdCoefficient : web3.toWei('1.5','ether'),
      capCoefficient : web3.toWei('2','ether'),
      roundCount : '3',
      // 1 hour : 60*(60/15) = 240 block
      // 1 day : 24*60*(60/15) = 5760 block
      roundZero : {
        roundIndex : '0',
        startBlock : '1204703', // Seoul 8 Nov Fri 11:00AM
        endBlock : '1205063', // Seoul 8 Nov Fri 12:30PM
        targetPercentage : web3.toWei('0.1','ether')
      },
      roundOne : {
        roundIndex : '1',
        startBlock : '1205183', // Seoul 8 Nov Fri 15:30PM
        endBlock : '1210943', // Seoul 9 Nov Fri 15:30PM
        targetPercentage : web3.toWei('0.3','ether')
      },
      roundTwo : {
        roundIndex : '2',
        startBlock : '1211663', // Seoul 9 Nov Fri 18:30PM
        endBlock : '1217423', // Seoul 10 Nov Fri 18:30PM
        targetPercentage : web3.toWei('0.3','ether')
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
                                  console.log(resRnd2Init);
                                  return null;
                                }
                              });
                            } else {
                              console.log(resRnd1Init);
                              return null;
                            }
                          });
                        } else {
                          console.log(resRnd0Init);
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
