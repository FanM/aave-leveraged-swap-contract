// We require the Hardhat Runtime Environment explicitly here. This is optional
// but useful for running the script in a standalone fashion through `node <script>`.
//
// When running the script with `npx hardhat run <script>` you'll find the Hardhat
// Runtime Environment's members available in the global scope.
import { ethers } from "hardhat";

async function main() {
  // Hardhat always runs the compile task when running scripts with its command
  // line interface.
  //
  // If this script is run directly using `node` you may want to call compile
  // manually to make sure everything is compiled
  // await hre.run('compile');

  const accounts = await ethers.getSigners();
  const adminAccount = accounts[0];
  // We get the contract to deploy
  const AaveLeveragedSwapManager = await ethers.getContractFactory(
    "AaveLeveragedSwapManager"
  );
  const aaveManagerImpl = await AaveLeveragedSwapManager.deploy();
  await aaveManagerImpl.deployed();
  console.log("AaveLeveragedSwapManager deployed to:", aaveManagerImpl.address);

  const Proxy = await ethers.getContractFactory("TransparentUpgradeableProxy");
  const proxy = Proxy.attach(process.env.AAVE_MANAGER_PROXY_ADDR!);
  await proxy.upgradeTo(aaveManagerImpl.address, {
    from: await adminAccount.getAddress(),
  });
  console.debug("Proxy successfully upgradeed.");
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
