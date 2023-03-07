import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";
import "@nomicfoundation/hardhat-chai-matchers"

const config: HardhatUserConfig = {
  mocha: {
    timeout: 100000000
  },
  solidity: {
    version: "0.8.17",
    settings: {
      optimizer: {
        enabled: true,
        runs: 200,
      },
    },
  },
  networks: {
    hardhat: {
      forking: {
        url: "https://eth-mainnet.g.alchemy.com/v2/1TJcRXXEnPv-UOMq7PixMTGik6Us2Wx9",
      },
      allowUnlimitedContractSize: true,
      // timeout: Number(100000000)
    },
    bsc_tesnet: {
      url: "https://data-seed-prebsc-1-s1.binance.org:8545",
      chainId: 97,
      gasPrice: 20e9,
      gas: 25e6,
      //0x758A6DDfcCDd68C26F51461F081B826832142464
      accounts: ["0x3c2b58fd5524a4907a7462a9a6d06bd41b2b5300af4648e2566ad5f48bac405b",],
      allowUnlimitedContractSize: true,
    },
    kcc_testnet: {
      url: "https://rpc-testnet.kcc.network/",
      chainId: 322,
      accounts: [
        "0x3c2b58fd5524a4907a7462a9a6d06bd41b2b5300af4648e2566ad5f48bac405b",
        "0x8815ae6cd0aed30bd8c89de3c44669f5e69dbf2f0843655fbd28d8ee93762235",
        "0xdd84e8a331de1f6debcdc7cec8b89b88b19c7616931b035d4c43b830fd33ec03",
        "0x1e552b81a9848f19885a6a204a895a54caf5f3d8f253d26cbb68f88cf3475afd",
        "0xafe7eda8541b57472915adce8a1b298954c936f7d28112fd01a6246742cfa67c",
        "0xd719d58908fdcf06e7da5876687c60e483b40c6ff3df9e3fd9ab3c0f34992bd1",
        "0x5026f6cbb11ef83363bff0ef1023f23878a7143f4e01cfc672cbbf632959074c"
      ],
      allowUnlimitedContractSize: true,
      timeout: 10000000,
    }
  },

};

export default config;
