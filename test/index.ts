import { expect } from "chai";
import { ethers } from "hardhat";
import { Signer } from "ethers";
import { BigNumber } from "@ethersproject/bignumber";
import Web3 from "web3";

import {
  LendingPoolAddressesProvider,
  ProtocalDataProvider,
  SushiswapRouter,
  WethGateway,
  NativeToken,
  DaiToken,
  UsdtToken,
  AaveToken,
} from "../.env.mainnet.json";

import {
  AaveLeveragedSwapManager,
  IProtocolDataProvider,
  IProtocolDataProvider__factory,
  IDebtToken__factory,
  ILendingPoolAddressesProvider__factory,
  IPriceOracleGetter__factory,
  IPriceOracleGetter,
  ILendingPool,
  ILendingPool__factory,
  IWETHGateway__factory,
  IERC20__factory,
  IERC20,
} from "../typechain";

const ETH_IN_WEI = BigInt(1e18);
const ABS_ERROR_ALLOWED = 1e15; // 0.001
const FEE_CALCULATION_SKEW = BigInt(5); // usually ±1 wei
const SLIPPAGE = BigInt(200); // 2%
const DEPOSIT_AMOUNT = BigInt(20) * ETH_IN_WEI;
const LOAN_WETH_AMOUNT = BigInt(50) * ETH_IN_WEI;
const REPAY_WETH_AMOUNT = BigInt(47) * ETH_IN_WEI;
const RATE_MODE = 2;

type TokenInfo = [
  string,
  boolean,
  boolean,
  boolean,
  BigNumber,
  BigNumber,
  BigNumber
] & {
  tokenAddress: string;
  borrowable: boolean;
  canBeCollateral: boolean;
  stableBorrowRateEnabled: boolean;
  liquidationThreshold: BigNumber;
  ltv: BigNumber;
  decimals: BigNumber;
};

type UserAccountData = [
  BigNumber,
  BigNumber,
  BigNumber,
  BigNumber,
  BigNumber,
  BigNumber
] & {
  totalCollateralETH: BigNumber;
  totalDebtETH: BigNumber;
  availableBorrowsETH: BigNumber;
  currentLiquidationThreshold: BigNumber;
  ltv: BigNumber;
  healthFactor: BigNumber;
};

type TokenAddresses = [string, string, string] & {
  aTokenAddress: string;
  stableDebtTokenAddress: string;
  variableDebtTokenAddress: string;
};

let aaveManager: AaveLeveragedSwapManager;
let dataProvider: IProtocolDataProvider;
let priceOracle: IPriceOracleGetter;
let lendingPool: ILendingPool;
let account: Signer;
let accountAddress: string;
let adminAccount: Signer;
let collateralTokenAddrs: TokenAddresses;
let targetTokenInfo: TokenInfo;
let targetTokenAddrs: TokenAddresses;
let targetToken: IERC20;
let pairTokenInfo: TokenInfo;
let pairTokenAddrs: TokenAddresses;
let pairToken: IERC20;
let aPairToken: IERC20;

before(async () => {
  [account, adminAccount] = await ethers.getSigners();
  accountAddress = await account.getAddress();
  const adminAddress = await adminAccount.getAddress();
  const AaveLeveragedSwapManager = await ethers.getContractFactory(
    "AaveLeveragedSwapManager"
  );
  const aaveManagerImpl = await AaveLeveragedSwapManager.connect(
    adminAccount
  ).deploy();

  await aaveManagerImpl.deployed();
  console.debug(
    "AaveLeveragedSwapManager deployed to:",
    aaveManagerImpl.address
  );

  const web3 = new Web3();
  const initParams = web3.eth.abi.encodeFunctionCall(
    {
      name: "initialize",
      type: "function",
      inputs: [
        {
          type: "address",
          name: "_addressProvider",
        },
        {
          type: "address",
          name: "_sushiRouter",
        },
        {
          type: "address",
          name: "_nativeETH",
        },
      ],
    },
    [LendingPoolAddressesProvider, SushiswapRouter, NativeToken]
  );
  const Proxy = await ethers.getContractFactory("TransparentUpgradeableProxy");
  const proxy = await Proxy.connect(adminAccount).deploy(
    aaveManagerImpl.address,
    adminAddress,
    initParams
  );
  console.debug("Proxy deployed to:", proxy.address);
  aaveManager = AaveLeveragedSwapManager.attach(proxy.address);

  const addressProvider = ILendingPoolAddressesProvider__factory.connect(
    LendingPoolAddressesProvider,
    account
  );
  dataProvider = IProtocolDataProvider__factory.connect(
    ProtocalDataProvider,
    account
  );
  lendingPool = ILendingPool__factory.connect(
    await addressProvider.getLendingPool(),
    account
  );
  // deposit native tokens as our collateral
  collateralTokenAddrs = await dataProvider.getReserveTokensAddresses(
    NativeToken
  );
  const aCollateralToken = IERC20__factory.connect(
    collateralTokenAddrs.aTokenAddress,
    account
  );
  const aCollateralBalance = await aCollateralToken.balanceOf(accountAddress);
  if (aCollateralBalance.toBigInt() < DEPOSIT_AMOUNT) {
    const wethGateway = IWETHGateway__factory.connect(WethGateway, account);
    wethGateway.depositETH(lendingPool.address, accountAddress, 0, {
      value: DEPOSIT_AMOUNT,
    });
  }
  priceOracle = IPriceOracleGetter__factory.connect(
    await addressProvider.getPriceOracle(),
    account
  );
  // choose Weth and Dai as our token pair because they both have 18 decimals thus
  // easier to work with ERC20 APIs
  targetTokenInfo = await aaveManager.getTokenInfo(NativeToken);
  targetTokenAddrs = await dataProvider.getReserveTokensAddresses(NativeToken);
  targetToken = IERC20__factory.connect(NativeToken, account);
  pairTokenInfo = await aaveManager.getTokenInfo(DaiToken);
  pairTokenAddrs = await dataProvider.getReserveTokensAddresses(DaiToken);
  pairToken = IERC20__factory.connect(DaiToken, account);
  aPairToken = IERC20__factory.connect(pairTokenAddrs.aTokenAddress, account);
});

describe("AaveLeveragedSwapManager", function () {
  async function getUserAccountData(): Promise<UserAccountData> {
    return await lendingPool.getUserAccountData(accountAddress);
  }
  it("Should fail if contract is initialized twice", async function () {
    await expect(
      aaveManager.initialize(
        LendingPoolAddressesProvider,
        SushiswapRouter,
        NativeToken
      )
    ).to.be.revertedWith("Initializable: contract is already initialized");
  });

  /*
  it("Should succeed listing asset tokens", async function () {
    const positions = await aaveManager.getAssetPositions();
    for (let position of positions) {
      if (position.token === NativeToken) {
        expect(position.borrowable).to.eq(true);
        expect(position.canBeCollateral).to.eq(true);
      } else if (position.token === AaveToken) {
        expect(position.borrowable).to.eq(false);
        expect(position.canBeCollateral).to.eq(true);
      } else if (position.token === UsdtToken) {
        expect(position.borrowable).to.eq(true);
        expect(position.canBeCollateral).to.eq(false);
      }
    }
  });
  */

  it("Should fail without asset delegation approvement", async function () {
    await expect(
      aaveManager.swapPreapprovedAssets(
        targetTokenInfo,
        LOAN_WETH_AMOUNT,
        pairTokenInfo,
        RATE_MODE,
        500
      )
    ).to.be.revertedWith("E2");
  });

  it("Should fail if the pair token is not collaterable", async function () {
    const usdtTokenInfo = await aaveManager.getTokenInfo(UsdtToken);
    await expect(
      aaveManager.checkAndCalculateSwapVars(
        targetTokenInfo,
        LOAN_WETH_AMOUNT,
        usdtTokenInfo,
        SLIPPAGE,
        true
      )
    ).to.be.revertedWith("E3");
  });

  it("Should fail if the target token is not borrowable", async function () {
    const aaveTokenInfo = await aaveManager.getTokenInfo(AaveToken);
    await expect(
      aaveManager.checkAndCalculateSwapVars(
        aaveTokenInfo,
        LOAN_WETH_AMOUNT,
        pairTokenInfo,
        SLIPPAGE,
        true
      )
    ).to.be.revertedWith("E4");
  });

  it("Should succeed swapping assets", async function () {
    const swapVars = await aaveManager.checkAndCalculateSwapVars(
      targetTokenInfo,
      LOAN_WETH_AMOUNT,
      pairTokenInfo,
      SLIPPAGE,
      true
    );
    console.debug(swapVars);

    const healthFactor = swapVars.expectedHealthFactor.toBigInt();

    let wethVariableDebtToken = IDebtToken__factory.connect(
      targetTokenAddrs.variableDebtTokenAddress,
      account
    );
    await wethVariableDebtToken.approveDelegation(
      aaveManager.address,
      LOAN_WETH_AMOUNT
    );
    const tx = await aaveManager.swapPreapprovedAssets(
      targetTokenInfo,
      LOAN_WETH_AMOUNT,
      pairTokenInfo,
      RATE_MODE,
      SLIPPAGE
    );

    const recept = await ethers.provider.getTransactionReceipt(tx.hash);
    console.debug(`Gas used: ${recept.gasUsed}`);
    const actualHealthFactor = (await getUserAccountData()).healthFactor;
    console.debug(`Actual Health Factor: ${actualHealthFactor}`);
    // verify the expected heath factor is within the error range
    expect(actualHealthFactor.sub(healthFactor).abs()).to.lt(ABS_ERROR_ALLOWED);
    // verify vars are cleared
    expect((await aaveManager.vars()).pairTokenAmount).to.eq(0);
    // verify aaveManager doesn't hold any pair tokens
    expect(await pairToken.balanceOf(aaveManager.address)).to.eq(0);
  });

  it("Should fail repaying if user did not approve aToken", async function () {
    let aPairTokenBalance = await aPairToken.balanceOf(accountAddress);
    const assets = [pairTokenInfo];
    const amounts = [aPairTokenBalance];
    await expect(
      aaveManager.repayDebt(
        assets,
        amounts,
        targetTokenInfo,
        REPAY_WETH_AMOUNT,
        RATE_MODE,
        SLIPPAGE
      )
    ).to.be.revertedWith("E12");
  });

  it("Should succeed repaying partial debt", async function () {
    let aPairTokenBalance = await aPairToken.balanceOf(accountAddress);
    const assets = [pairTokenInfo];
    const amounts = [aPairTokenBalance];
    const repayVars = await aaveManager.checkAndCalculateRepayVars(
      assets,
      amounts,
      targetTokenInfo,
      REPAY_WETH_AMOUNT,
      RATE_MODE,
      SLIPPAGE,
      true
    );
    console.debug(repayVars);
    const healthFactor = repayVars.expectedHealthFactor.toBigInt();

    await aPairToken.approve(aaveManager.address, aPairTokenBalance);
    const tx = await aaveManager.repayDebt(
      assets,
      amounts,
      targetTokenInfo,
      REPAY_WETH_AMOUNT,
      RATE_MODE,
      SLIPPAGE
    );

    const recept = await ethers.provider.getTransactionReceipt(tx.hash);
    console.debug(`Gas used: ${recept.gasUsed}`);
    const actualHealthFactor = (await getUserAccountData()).healthFactor;
    console.debug(`Actual Health Factor: ${actualHealthFactor}`);
    // verify the expected heath factor is within the error range
    expect(actualHealthFactor.sub(healthFactor).abs()).to.lt(ABS_ERROR_ALLOWED);
    // verify vars are cleared
    expect((await aaveManager.vars()).targetTokenAmount).to.eq(0);
    // verify aaveManager doesn't hold any target tokens
    expect(await targetToken.balanceOf(aaveManager.address)).to.eq(0);
  });

  it("Should succeed swapping assets with fees sent in", async function () {
    const swapVars = await aaveManager.checkAndCalculateSwapVars(
      targetTokenInfo,
      LOAN_WETH_AMOUNT,
      pairTokenInfo,
      SLIPPAGE,
      false // sends fee separately
    );
    console.debug(swapVars);

    const healthFactor = swapVars.expectedHealthFactor.toBigInt();

    let wethVariableDebtToken = IDebtToken__factory.connect(
      targetTokenAddrs.variableDebtTokenAddress,
      account
    );
    await wethVariableDebtToken.approveDelegation(
      aaveManager.address,
      LOAN_WETH_AMOUNT
    );
    const feeAmount =
      (swapVars.feeETH.toBigInt() * ETH_IN_WEI) /
      (await priceOracle.getAssetPrice(NativeToken)).toBigInt();
    const tx = await aaveManager.swapPreapprovedAssets(
      targetTokenInfo,
      LOAN_WETH_AMOUNT,
      pairTokenInfo,
      RATE_MODE,
      SLIPPAGE,
      {
        value: feeAmount + FEE_CALCULATION_SKEW,
      }
    );

    const recept = await ethers.provider.getTransactionReceipt(tx.hash);
    console.debug(`Gas used: ${recept.gasUsed}`);
    const actualHealthFactor = (await getUserAccountData()).healthFactor;
    console.debug(`Actual Health Factor: ${actualHealthFactor}`);
    expect(actualHealthFactor.sub(healthFactor).abs()).to.lt(ABS_ERROR_ALLOWED);
    expect((await aaveManager.vars()).pairTokenAmount).to.eq(0);
  });

  it("Should succeed repaying total debt with fees sent in", async function () {
    const collateralTokenInfo = await aaveManager.getTokenInfo(NativeToken);
    const aCollateralToken = IERC20__factory.connect(
      collateralTokenAddrs.aTokenAddress,
      account
    );
    const aCollateralTokenBalance = (
      await aCollateralToken.balanceOf(accountAddress)
    )
      .mul(9)
      .div(10); // do not use the exact aToken balance as the reduced amount
    // will exceed totalCollateralETH * currentLiquidationThreshold

    const aPairTokenBalance = await aPairToken.balanceOf(accountAddress);
    const assets = [pairTokenInfo, collateralTokenInfo];
    const amounts = [aPairTokenBalance, aCollateralTokenBalance];

    let targetVariableDebtToken = IERC20__factory.connect(
      targetTokenAddrs.variableDebtTokenAddress,
      account
    );
    const repaidAmount = await targetVariableDebtToken.balanceOf(
      accountAddress
    );
    const repayVars = await aaveManager.checkAndCalculateRepayVars(
      assets,
      amounts,
      targetTokenInfo,
      repaidAmount,
      RATE_MODE,
      SLIPPAGE,
      false // sends fee separately
    );
    console.debug(repayVars);

    await aPairToken.approve(aaveManager.address, aPairTokenBalance);
    await aCollateralToken.approve(
      aaveManager.address,
      aCollateralTokenBalance
    );
    const feeAmount =
      (repayVars.feeETH.toBigInt() * ETH_IN_WEI) /
      (await priceOracle.getAssetPrice(NativeToken)).toBigInt();
    const tx = await aaveManager.repayDebt(
      assets,
      amounts,
      targetTokenInfo,
      repaidAmount,
      RATE_MODE,
      SLIPPAGE,
      {
        value: feeAmount + FEE_CALCULATION_SKEW,
      }
    );
    const recept = await ethers.provider.getTransactionReceipt(tx.hash);
    console.debug(`Gas used: ${recept.gasUsed}`);
    const debtAfterRepay = (await getUserAccountData()).totalDebtETH;
    console.debug(`Debt after repay: ${debtAfterRepay}`);
    expect((await aaveManager.vars()).targetTokenAmount).to.eq(0);
    // verify aaveManager doesn't hold any target tokens
    expect(await targetToken.balanceOf(aaveManager.address)).to.eq(0);
  });
});
