// We require the Hardhat Runtime Environment explicitly here. This is optional
// but useful for running the script in a standalone fashion through `node <script>`.
//
// When running the script with `npx hardhat run <script>` you'll find the Hardhat
// Runtime Environment's members available in the global scope.
import { ethers } from "hardhat";
import {
  LendingPoolAddressesProvider,
  SushiswapRouter,
  NativeToken,
} from "../.env.polygon.json";

async function main() {
  // Hardhat always runs the compile task when running scripts with its command
  // line interface.
  //
  // If this script is run directly using `node` you may want to call compile
  // manually to make sure everything is compiled
  // await hre.run('compile');
  const [deployerAccount] = await ethers.getSigners();
  const deployerAddress = await deployerAccount.getAddress();
  console.debug("Deployer address: ", deployerAddress);

  if (process.env.PROXY_ADMIN_ADDRESS === undefined) {
    console.error("Please set PROXY_ADMIN_ADDRESS ENV variable first.");
    return;
  } else if (process.env.PROXY_ADMIN_ADDRESS === deployerAddress) {
    console.error("PROXY_ADMIN_ADDRESS cannot be the deployer account.");
    return;
  }

  // We get the contract to deploy
  const AaveLeveragedSwapManager = await ethers.getContractFactory(
    "AaveLeveragedSwapManager"
  );
  const aaveManagerImpl = await AaveLeveragedSwapManager.deploy();
  await aaveManagerImpl.deployed();
  console.log("AaveLeveragedSwapManager deployed to:", aaveManagerImpl.address);

  const Proxy = await ethers.getContractFactory("TransparentUpgradeableProxy");
  const proxy = await Proxy.deploy(
    aaveManagerImpl.address,
    process.env.PROXY_ADMIN_ADDRESS,
    [] //initParams
  );
  console.debug("Proxy deployed to:", proxy.address);

  const aaveManager = AaveLeveragedSwapManager.attach(proxy.address);
  try {
    await aaveManager.initialize(
      LendingPoolAddressesProvider,
      SushiswapRouter,
      NativeToken
    );
    console.debug("AaveLeveragedSwapManager initialized");
  } catch (e: any) {
    console.error(e.message);
  }
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
