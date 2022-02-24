import * as dotenv from "dotenv";

import { BigNumber } from "ethers";
import { HardhatUserConfig, task } from "hardhat/config";
import "@nomiclabs/hardhat-etherscan";
import "@nomiclabs/hardhat-waffle";
import "@nomiclabs/hardhat-web3";
import "@typechain/hardhat";
import "hardhat-gas-reporter";
import { AbiItem } from "web3-utils";
import "solidity-coverage";

dotenv.config();

// This is a sample Hardhat task. To learn how to create your own go to
// https://hardhat.org/guides/create-task.html
task("accounts", "Prints the list of accounts", async (taskArgs, hre) => {
  const accounts = await hre.ethers.getSigners();

  for (const account of accounts) {
    console.log(account.address);
  }
});

task("swap", "Make a leveraged swap", async (taskArgs, hre) => {
  await hre.run("compile");
  const AaveManagerContract = await import(
    "./artifacts/contracts/AaveLeveragedSwapManager.sol/AaveLeveragedSwapManager.json"
  );
  const ProtocolDataProviderContract = await import(
    "./artifacts/contracts/interfaces/IProtocolDataProvider.sol/IProtocolDataProvider.json"
  );
  const IDebtTokenContract = await import(
    "./artifacts/contracts/interfaces/IDebtToken.sol/IDebtToken.json"
  );
  const { ProtocalDataProvider } = await import("./.env.polygon.json");

  const [admin, user] = await hre.ethers.getSigners();
  const userAddress = await user.getAddress();
  console.log("User address: ", userAddress);

  const targetTokenAddr = "";
  const targetTokenAmount = BigNumber.from(10).pow(18);
  const pairTokenAddr = "";
  const deployedContract = process.env.AAVE_MANAGER_PROXY_ADDR;

  const aaveContract = new hre.web3.eth.Contract(
    AaveManagerContract.abi as AbiItem[],
    deployedContract
  );
  const protocolDataProvider = new hre.web3.eth.Contract(
    ProtocolDataProviderContract.abi as AbiItem[],
    ProtocalDataProvider
  );
  const targetDebtTokenAddress = (
    await protocolDataProvider.methods
      .getReserveTokensAddresses(targetTokenAddr)
      .call()
  ).variableDebtTokenAddress;

  const targetIDebtToken = new hre.web3.eth.Contract(
    IDebtTokenContract.abi as AbiItem[],
    targetDebtTokenAddress
  );
  await targetIDebtToken.methods
    .approveDelegation(deployedContract, targetTokenAmount)
    .send({ from: userAddress });

  const targetToken = await aaveContract.methods
    .getTokenInfo(targetTokenAddr)
    .call();
  const pairToken = await aaveContract.methods
    .getTokenInfo(pairTokenAddr)
    .call();
  await aaveContract.methods
    .swapPreapprovedAssets(targetToken, targetTokenAmount, pairToken, 2, 200)
    .send({ from: userAddress });
});

// You need to export an object to set up your config
// Go to https://hardhat.org/config/ to learn more

const config: HardhatUserConfig = {
  solidity: {
    version: "0.8.6",
    settings: {
      optimizer: {
        enabled: true,
        runs: 200,
      },
    },
  },
  mocha: {
    timeout: 400000,
  },
  networks: {
    localhost: {
      url: "http://127.0.0.1:8545",
      timeout: 1000000,
    },
    hardhat: {
      forking: {
        url:
          process.env.INFURA_API_KEY !== undefined
            ? `https://mainnet.infura.io/v3/${process.env.INFURA_API_KEY}`
            : "",
      },
      accounts:
        process.env.PRIVATE_KEY_ADMIN !== undefined &&
        process.env.PRIVATE_KEY_USER !== undefined
          ? [
              {
                privateKey: process.env.PRIVATE_KEY_ADMIN!,
                balance: "100000000000000000000",
              },
              {
                privateKey: process.env.PRIVATE_KEY_USER,
                balance: "100000000000000000000",
              },
            ]
          : [],
    },
    kovan: {
      url: "https://kovan.poa.network",
      chainId: 42,
      accounts:
        process.env.PRIVATE_KEY_DEPLOYER !== undefined
          ? [process.env.PRIVATE_KEY_DEPLOYER]
          : [],
      gas: 3000000,
    },
    polygon: {
      url: "https://polygon-rpc.com",
      chainId: 137,
      accounts:
        process.env.PRIVATE_KEY_DEPLOYER !== undefined
          ? [process.env.PRIVATE_KEY_DEPLOYER]
          : [],
      gas: 3000000,
    },
    mumbai: {
      url: "https://rpc-mumbai.matic.today",
      chainId: 80001,
      accounts:
        process.env.PRIVATE_KEY_DEPLOYER !== undefined
          ? [process.env.PRIVATE_KEY_DEPLOYER]
          : [],
      gas: 3000000,
    },
  },
  gasReporter: {
    enabled: process.env.REPORT_GAS !== undefined,
    currency: "USD",
  },
  etherscan: {
    apiKey: process.env.POLYGONSCAN_API_KEY,
  },
};

export default config;
