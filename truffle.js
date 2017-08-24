module.exports = {
  networks: {
    development: {
      host: "localhost",
      port: 8545,
      network_id: "*" // Match any network id
    },
    ropsten: {
      network_id: 3, // ropsten testnet
      host: "localhost",
      port: 8546,
      gas: 4712384,
      gasPrice: 900000000000 // 900 Shannon
    },
    rinkeby: {
      network_id: 4, // rinkeby testnet
      host: "localhost",
      port: 8547,
      gas: 4500000
      // gasPrice: 100000000000 // defulat 100 Shannon
    },
    live: {
      network_id: 1,
      host: "localhost",
      port: 8548,
      gas: 4712384
      // gasPrice: 100000000000 // default 100 Shannon
    }
  }
};
