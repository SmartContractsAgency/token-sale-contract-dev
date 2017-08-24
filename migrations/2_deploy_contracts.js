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
      initSupply : web3.toWei('100000000','ether'),
      postContribController : '0x0000000000000000000000000000000000000001',
      initMinTarget : web3.toWei('312500','ether'),
      initMaxTarget : web3.toWei('1562500','ether'),
      basePercentage : web3.toWei('0.1','ether'),
      perRoundPercentage : web3.toWei('0.05','ether'),
      thresholdCoefficient : web3.toWei('1.5','ether'),
      capCoefficient : web3.toWei('2','ether')
    }
  } else if (network == "ropsten") { // ropsten testnet

  } else if (network == "rinkeby") { // rinkeby testnet

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
                      t.address, asxContribution.initMinTarget, asxContribution.initMaxTarget,
                      asxContribution.basePercentage, asxContribution.perRoundPercentage,
                      asxContribution.thresholdCoefficient, asxContribution.capCoefficient
                  ).then(function (resInit) {
                    if (resInit.logs && resInit.logs.length > 0 && resInit.logs[0].event == 'Init') {
                      console.log(resInit.logs[0]);
                      console.log('ASXContribution.initialize() Success!');
                      return newASXC;
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
