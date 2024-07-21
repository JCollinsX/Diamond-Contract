import { HardhatUserConfig, HttpNetworkAccountsUserConfig } from 'hardhat/types'
import "hardhat-deploy-ethers";
import "hardhat-deploy";
import "@nomicfoundation/hardhat-toolbox";
import "hardhat-contract-sizer";
import "@matterlabs/hardhat-zksync-solc";

import { resolve } from "path";
import { config as dotenvConfig } from "dotenv";

dotenvConfig({ path: resolve(__dirname, "./.env") });

export const chainIds = {
  // Dev
  hardhat: 31337,

  // Test
  okcTest: 65,
  confluxTest: 71,
  bscTest: 97,
  velasTest: 111,
  hecoTest: 256,
  zksync_sepolia: 300,
  kucoinTest: 322,
  cronosTest: 338,
  pulseTest: 941,
  ftmTest: 4002,
  avaxTest: 43113,
  maticTest: 80001,
  baseTest: 84531,
  sepolia: 11155111,
  berachain: 80085,
  taiko: 167008,
  blast_sepolia: 168587773,

  // Production
  eth: 1,
  optimism: 10,
  cronos: 25,
  bsc: 56,
  okx: 66,
  velas: 106,
  heco: 128,
  matic: 137,
  opbnb: 204,
  ftm: 250,
  kucoin: 321,
  zksync: 324,
  pulse: 369,
  conflux: 1030,
  doge: 2000,
  base: 8453,
  evmos: 9001,
  arbitrum: 42161,
  avax: 43114,
  linea: 59144,
  blast: 81457,
};

// Set your preferred authentication method
//
// If you prefer using a mnemonic, set a MNEMONIC environment variable
// to a valid mnemonic
const MNEMONIC = process.env.MNEMONIC

// If you prefer to be authenticated using a private key, set a PRIVATE_KEY environment variable
const PRIVATE_KEY = process.env.PRIVATE_KEY

const accounts: HttpNetworkAccountsUserConfig | undefined = MNEMONIC
    ? { mnemonic: MNEMONIC }
    : PRIVATE_KEY
      ? [PRIVATE_KEY]
      : undefined

if (accounts == null) {
    console.warn(
        'Could not find MNEMONIC or PRIVATE_KEY environment variables. It will not be possible to execute transactions in your example.'
    )
}

const config: HardhatUserConfig = {
  defaultNetwork: "hardhat",
  gasReporter: {
    currency: "USD",
    enabled: true,
    excludeContracts: [],
    src: "./contracts",
  },
  namedAccounts: {
    deployer: {
      default: process.env.DEPLOYER_ADDRESS || "",
    },
  },
  networks: {
    hardhat: {
      chainId: chainIds["eth"],
      // allowUnlimitedContractSize: true,
      allowBlocksWithSameTimestamp: false,
      gas: 8000000,
      forking: {
        url: "https://rpc.ankr.com/eth",
      },
      mining: {
        auto: true,
        interval: 0,
      },
    },
    eth: {
      accounts,
      chainId: chainIds["eth"],
      url: `https://eth.public-rpc.com`,
    },
    sepolia: {
      accounts,
      chainId: chainIds["sepolia"],
      url: `https://rpc.ankr.com/eth_sepolia`,
    },
    bsc: {
      accounts,
      chainId: chainIds["bsc"],
      url: "https://bsc-dataseed.binance.org/",
    },
  },
  paths: {
    artifacts: "./artifacts",
    cache: "./cache",
    sources: "./contracts",
    tests: "./test",
  },
  solidity: {
    version: "0.8.23",
    settings: {
      metadata: {
        // Not including the metadata hash
        // https://github.com/paulrberg/solidity-template/issues/31
        bytecodeHash: "none",
      },
      // Disable the optimizer when debugging
      // https://hardhat.org/hardhat-network/#solidity-optimizer-support
      optimizer: {
        enabled: true,
        runs: 10,
      },
    },
  },
  typechain: {
    outDir: "src/types",
    target: "ethers-v5",
  },
  mocha: {
    timeout: 100000000,
  },
};

export default config;
