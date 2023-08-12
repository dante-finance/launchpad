require("@nomiclabs/hardhat-etherscan");
require("@nomicfoundation/hardhat-toolbox");
require("@nomicfoundation/hardhat-chai-matchers");
require("@ethersproject/bignumber");

let secret = require("./secret"); 

task("accounts", "Prints the list of accounts", async (taskArgs, hre) => {
  const accounts = await hre.ethers.getSigners();

  for (const account of accounts) {
    console.log(account.address);
  }
});
// You need to export an object to set up your config
// Go to https://hardhat.org/config/ to learn more

/**
 * @type import('hardhat/config').HardhatUserConfig
 */
module.exports = {
  solidity: {
    compilers: [
      {
        version: "0.8.9",
        settings: {
          optimizer: {
            enabled: true,
            runs: 1000,
          },
        }
      }
    ]
  },
  networks: {
    hardhat: {
      allowUnlimitedContractSize: true
    },
    localhost: {
      allowUnlimitedContractSize: true
    },
    ethereum: {
      url: secret.url,
      accounts: [secret.key],
      gas: "auto",
      gasPrice: "auto",
      gasMultiplier: 1.5,
      allowUnlimitedContractSize: true
    },
    arbitrum: {
      url: secret.url,
      accounts: [secret.key],
      gas: "auto",
      gasPrice: "auto",
      gasMultiplier: 1,
      allowUnlimitedContractSize: true
    },
    testnet: {
      url: secret.url,
      accounts: [secret.key],
      gas: "auto",
      gasPrice: "auto",
      gasMultiplier: 1,
      allowUnlimitedContractSize: false
    },
    mainnet: {
      url: secret.url,
      accounts: [secret.key],
      gas: "auto",
      gasPrice: "auto",
      gasMultiplier: 1,
      allowUnlimitedContractSize: false
    }
  },
  etherscan: {
    apiKey: "73GCA4SQIRJ687YKMSQUIVPUA9TGSXQHMC"
  }
};
