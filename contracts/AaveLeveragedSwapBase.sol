//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./interfaces/IAaveLeveragedSwapManager.sol";
import "./interfaces/ILendingPool.sol";
import "./interfaces/IProtocolDataProvider.sol";
import "./interfaces/IPriceOracle.sol";
import "./interfaces/IUniswapV2Router02.sol";
import "./interfaces/IWeth.sol";
import "./utils/EnumerableMap.sol";
import "./utils/PercentageMath.sol";
import "./utils/WadRayMath.sol";
import "./utils/Errors.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

abstract contract AaveLeveragedSwapBase is IAaveLeveragedSwapManager {
  using SafeERC20 for IERC20;
  using WadRayMath for uint256;
  using PercentageMath for uint256;
  using EnumerableMap for EnumerableMap.AddressToUintsMap;

  struct FlashLoanVars {
    uint targetTokenAmount;
    uint pairTokenAmount; // leverage only
    uint feeTokenAmount;
    uint loanETH; // leverage only
    uint feeETH;
    uint slippage;
    uint borrowRateMode;
    TokenInfo targetToken;
    TokenInfo pairToken; // leverage only
    address user;
  }

  struct SwapVars {
    uint loanETH;
    uint maxLoanETH;
    uint feeETH;
    uint flashLoanETH;
    uint currentHealthFactor;
    uint expectedHealthFactor;
  }

  struct RepayVars {
    uint loanETH;
    uint feeETH;
    uint totalCollateralReducedETH;
    uint flashLoanETH;
    uint currentHealthFactor;
    uint expectedHealthFactor;
    uint[] reducedCollateralValues;
  }

  uint public constant FLASH_LOAN_FEE_RATE = 9; // 0.09%
  bytes32 public constant PROTOCOL_DATA_PROVIDER_ID = bytes32(uint(1)) << 248; // 0x01

  ILendingPoolAddressesProvider ADDRESSES_PROVIDER;
  ILendingPool LENDING_POOL;
  IProtocolDataProvider DATA_PROVIDER;
  IPriceOracleGetter PRICE_ORACLE;
  IUniswapV2Router02 SUSHI_ROUTER;
  address NATIVE_ETH;

  EnumerableMap.AddressToUintsMap assetMap; // tokens to tokenValueETH map
  FlashLoanVars public vars;

  modifier onlyLendingPool() {
    require(
      msg.sender == address(LENDING_POOL),
      Errors.CONTRACT_ONLY_CALLED_BY_LENDING_POOL
    );
    _;
  }

  function getAssetPositions()
    external
    view
    override
    returns (Position[] memory positions)
  {
    IProtocolDataProvider.TokenData[] memory tokenList = DATA_PROVIDER
      .getAllReservesTokens();
    positions = new Position[](tokenList.length);
    for (uint i = 0; i < tokenList.length; i++) {
      TokenInfo memory tokenInfo = getTokenInfo(tokenList[i].tokenAddress);

      (
        uint aTokenBalance,
        uint stableDebt,
        uint variableDebt,
        uint principalStableDebt,
        uint scaledVariableDebt,
        ,
        ,
        ,
        bool usedAsCollateral
      ) = DATA_PROVIDER.getUserReserveData(
          tokenList[i].tokenAddress,
          msg.sender
        );

      positions[i] = Position(
        tokenList[i].symbol,
        tokenList[i].tokenAddress,
        aTokenBalance,
        stableDebt,
        variableDebt,
        principalStableDebt,
        scaledVariableDebt,
        usedAsCollateral,
        tokenInfo.borrowable,
        tokenInfo.canBeCollateral,
        tokenInfo.stableBorrowRateEnabled
      );
    }
  }

  /**
   * @dev calculate swap variables and do sanity check
   */
  function checkAndCalculateSwapVars(
    TokenInfo memory _targetToken,
    uint _targetTokenAmount,
    TokenInfo memory _pairToken,
    uint _slippage,
    bool _feePaidByCollateral
  ) public view returns (SwapVars memory swapVars) {
    // pairToken should be able to use as collateral
    require(
      _pairToken.canBeCollateral,
      Errors.LEVERAGE_PAIR_TOKEN_NOT_COLLATERABLE
    );
    uint totalCollateralETH;
    uint currentLiquidationThreshold;
    uint userAvailableBorrowsETH;
    uint existDebtETH;
    (
      totalCollateralETH,
      existDebtETH,
      userAvailableBorrowsETH,
      currentLiquidationThreshold,
      ,
      swapVars.currentHealthFactor
    ) = LENDING_POOL.getUserAccountData(msg.sender);

    // targetToken should be borrowable
    require(
      _targetToken.borrowable,
      Errors.LEVERAGE_TARGET_TOKEN_NOT_BORROWABLE
    );

    // calculate the amount in ETH we need to borrow for targetToken
    swapVars.loanETH = PRICE_ORACLE
      .getAssetPrice(_targetToken.tokenAddress)
      .wadMul(_targetTokenAmount);

    swapVars.flashLoanETH = swapVars.loanETH.percentMul(
      PercentageMath.PERCENTAGE_FACTOR - _slippage
    );

    // calculates max loanable after depositing back
    // for details refer to math.md
    uint tempTerm1 = PercentageMath.PERCENTAGE_FACTOR -
      _pairToken.ltv.percentMul(PercentageMath.PERCENTAGE_FACTOR - _slippage);
    if (_feePaidByCollateral) {
      uint tempTerm2 = PercentageMath.PERCENTAGE_FACTOR + FLASH_LOAN_FEE_RATE;
      swapVars.flashLoanETH = swapVars.flashLoanETH.percentDiv(tempTerm2);
      tempTerm1 += FLASH_LOAN_FEE_RATE;
      swapVars.maxLoanETH = userAvailableBorrowsETH
        .percentMul(tempTerm2)
        .percentDiv(tempTerm1);
    } else {
      swapVars.maxLoanETH = userAvailableBorrowsETH.percentDiv(tempTerm1);
    }

    swapVars.feeETH = swapVars.flashLoanETH.percentMul(FLASH_LOAN_FEE_RATE);
    if (!_feePaidByCollateral) {
      // consider the slippage
      swapVars.feeETH = swapVars.feeETH.percentDiv(
        PercentageMath.PERCENTAGE_FACTOR - _slippage
      );
    }
    uint newCollateral = swapVars.flashLoanETH.percentMul(
      _pairToken.liquidationThreshold
    ) + totalCollateralETH.percentMul(currentLiquidationThreshold);
    uint newDebt = existDebtETH + swapVars.loanETH;
    swapVars.expectedHealthFactor = newDebt == 0
      ? type(uint).max
      : newCollateral.wadDiv(newDebt);
  }

  /**
   * @dev calculate repay variables and do sanity check
   */
  function checkAndCalculateRepayVars(
    TokenInfo[] memory _assets,
    uint[] memory _amounts,
    TokenInfo memory _targetToken,
    uint _targetAmount,
    uint _rateMode,
    uint _slippage,
    bool _feePaidByCollateral
  ) public view returns (RepayVars memory repayVars) {
    repayVars.flashLoanETH = _tryGetUserDebtPosition(
      _targetToken,
      _targetAmount,
      _rateMode,
      msg.sender
    );
    uint totalCollateralETH;
    uint currentLiquidationThreshold;
    uint existDebtETH;
    (
      totalCollateralETH,
      existDebtETH,
      ,
      currentLiquidationThreshold,
      ,
      repayVars.currentHealthFactor
    ) = LENDING_POOL.getUserAccountData(msg.sender);

    require(
      _assets.length == _amounts.length,
      Errors.DELEVERAGE_MISMATCHED_ASSETS_AND_AMOUNTS
    );
    repayVars.reducedCollateralValues = new uint[](_assets.length);

    totalCollateralETH = totalCollateralETH.percentMul(
      currentLiquidationThreshold
    );
    // depends on caller to ensure no duplicate entries
    for (uint i = 0; i < _assets.length; i++) {
      (
        uint tokenValueETH,
        bool userUsedAsCollateralEnabled
      ) = _tryGetUserTokenETH(_assets[i], _amounts[i], msg.sender);
      require(
        userUsedAsCollateralEnabled && _assets[i].canBeCollateral,
        Errors.DELEVERAGE_ASSET_TOKEN_CANNOT_BE_COLLATERAL
      );
      repayVars.reducedCollateralValues[i] = tokenValueETH;
      repayVars.totalCollateralReducedETH += tokenValueETH;
      // reuse local variable to avoid stack too deep
      tokenValueETH = tokenValueETH.percentMul(_assets[i].liquidationThreshold);
      // this is possible as (totalCollateralETH * currentLiquidationThreshold)
      // can be a little less than the sum of (tokenValueETH * liquidationThreshold),
      // although totalCollateralETH = sum(tokenValueETH)
      require(
        totalCollateralETH > tokenValueETH,
        Errors.DELEVERAGE_REDUCED_ASSET_EXCCEED_NEEDED
      );
      unchecked {
        totalCollateralETH -= tokenValueETH;
      }
    }
    repayVars.feeETH = repayVars.flashLoanETH.percentMul(FLASH_LOAN_FEE_RATE);
    if (_feePaidByCollateral) {
      repayVars.loanETH = repayVars.flashLoanETH + repayVars.feeETH;
    } else {
      repayVars.loanETH = repayVars.flashLoanETH;
      repayVars.feeETH = repayVars.feeETH.percentDiv(
        PercentageMath.PERCENTAGE_FACTOR - _slippage
      );
    }
    // consider the slippage
    repayVars.loanETH = repayVars.loanETH.percentDiv(
      PercentageMath.PERCENTAGE_FACTOR - _slippage
    );

    if (existDebtETH <= repayVars.flashLoanETH) {
      // user's debt is cleared
      repayVars.expectedHealthFactor = type(uint).max;
    } else {
      unchecked {
        repayVars.expectedHealthFactor = totalCollateralETH.wadDiv(
          existDebtETH - repayVars.flashLoanETH
        );
      }
    }
  }

  function getTokenInfo(address _token)
    public
    view
    returns (TokenInfo memory tokenInfo)
  {
    tokenInfo.tokenAddress = _token;
    bool isActive;
    bool isFrozen;
    (
      tokenInfo.decimals,
      tokenInfo.ltv,
      tokenInfo.liquidationThreshold,
      ,
      ,
      tokenInfo.canBeCollateral,
      tokenInfo.borrowable,
      tokenInfo.stableBorrowRateEnabled,
      isActive,
      isFrozen
    ) = DATA_PROVIDER.getReserveConfigurationData(_token);
    tokenInfo.canBeCollateral =
      tokenInfo.canBeCollateral &&
      (isActive && !isFrozen);
    tokenInfo.borrowable = tokenInfo.borrowable && (isActive && !isFrozen);
  }

  function _tryGetUserTokenETH(
    TokenInfo memory _token,
    uint _amount,
    address _user
  )
    private
    view
    returns (uint tokenValueETH, bool userUsedAsCollateralEnabled)
  {
    uint aTokenBalance;
    (aTokenBalance, , , , , , , , userUsedAsCollateralEnabled) = DATA_PROVIDER
      .getUserReserveData(_token.tokenAddress, _user);
    require(
      aTokenBalance >= _amount,
      Errors.DELEVERAGE_ATOKEN_SPECIFIED_EXCEEDS_OWNED
    );
    tokenValueETH = PRICE_ORACLE.getAssetPrice(_token.tokenAddress).wadMul(
      _amount
    );
  }

  function _tryGetUserDebtPosition(
    TokenInfo memory _targetToken,
    uint _targetTokenAmount,
    uint _borrowRateMode,
    address _user
  ) private view returns (uint) {
    (, uint stableDebt, uint variableDebt, , , , , , ) = DATA_PROVIDER
      .getUserReserveData(_targetToken.tokenAddress, _user);
    if (_borrowRateMode == 1) {
      // stable debt
      require(
        _targetTokenAmount <= stableDebt,
        Errors.DELEVERAGE_STABLE_DEBT_SPECIFIED_EXCEEDS_OWNED
      );
    } else if (_borrowRateMode == 2) {
      // variable debt
      require(
        _targetTokenAmount <= variableDebt,
        Errors.DELEVERAGE_VARIABLE_DEBT_SPECIFIED_EXCEEDS_OWNED
      );
    } else {
      revert("Invalid borrow rate mode!");
    }
    return
      PRICE_ORACLE.getAssetPrice(_targetToken.tokenAddress).wadMul(
        _targetTokenAmount
      );
  }

  function _getSushiSwapTokenPath(address fromToken, address toToken)
    private
    pure
    returns (address[] memory path)
  {
    path = new address[](2);
    path[0] = fromToken;
    path[1] = toToken;

    return path;
  }

  function transferUserATokenToContract(
    TokenInfo memory _token,
    uint _amount,
    address _user
  ) internal {
    // get aToken address
    (address aTokenAddress, , ) = DATA_PROVIDER.getReserveTokensAddresses(
      _token.tokenAddress
    );
    // user must have approved this contract to use their funds in advance
    try
      IERC20(aTokenAddress).transferFrom(
        _user,
        address(this),
        _amount.wadToDecimals(_token.decimals) // converts to token's decimals
      )
    returns (bool succeeded) {
      if (!succeeded) {
        revert(Errors.DELEVERAGE_ATOKEN_TRANSFER_FAILED_WITH_UNKNOWN_REASON);
      }
    } catch Error(
      string memory /*reason*/
    ) {
      revert(Errors.DELEVERAGE_USER_DID_NOT_APPROVE_ATOKEN_TRANSFER);
    }
  }

  function convertEthToTokenAmount(uint valueETH, TokenInfo memory token)
    internal
    view
    returns (uint)
  {
    return valueETH.wadDiv(PRICE_ORACLE.getAssetPrice(token.tokenAddress));
  }

  function swapExactETHForTokens(
    uint amountIn, // wad
    TokenInfo memory outToken,
    uint amountOutMin, // wad
    address onBehalfOf
  ) internal returns (uint) {
    if (NATIVE_ETH == outToken.tokenAddress) {
      IWETH(NATIVE_ETH).deposit{value: amountIn}();
      return amountIn;
    }
    amountOutMin = amountOutMin.wadToDecimals(outToken.decimals);
    try
      SUSHI_ROUTER.swapExactETHForTokens{value: amountIn}(
        amountOutMin,
        _getSushiSwapTokenPath(NATIVE_ETH, outToken.tokenAddress),
        onBehalfOf,
        block.timestamp
      )
    returns (uint[] memory amounts) {
      return amounts[1].decimalsToWad(outToken.decimals);
    } catch Error(
      string memory /*reason*/
    ) {
      revert(Errors.OPS_NOT_ABLE_TO_EXCHANGE_BY_SPECIFIED_SLIPPAGE);
    }
  }

  function approveAndSwapExactTokensForTokens(
    TokenInfo memory inToken,
    uint amountIn, // wad
    TokenInfo memory outToken,
    uint amountOutMin, // wad
    address onBehalfOf
  ) internal returns (uint) {
    if (inToken.tokenAddress == outToken.tokenAddress) {
      return amountIn;
    }
    // converts wad to the token units
    amountIn = amountIn.wadToDecimals(inToken.decimals);
    amountOutMin = amountOutMin.wadToDecimals(outToken.decimals);
    IERC20(inToken.tokenAddress).safeApprove(address(SUSHI_ROUTER), amountIn);

    try
      SUSHI_ROUTER.swapExactTokensForTokens(
        amountIn,
        amountOutMin,
        _getSushiSwapTokenPath(inToken.tokenAddress, outToken.tokenAddress),
        onBehalfOf,
        block.timestamp
      )
    returns (uint[] memory amounts) {
      return amounts[1].decimalsToWad(outToken.decimals);
    } catch Error(
      string memory /*reason*/
    ) {
      revert(Errors.OPS_NOT_ABLE_TO_EXCHANGE_BY_SPECIFIED_SLIPPAGE);
    }
  }

  function cleanUpAfterSwap() internal {
    // reset vars
    delete vars;
    // clear the address map
    for (uint i = 0; i < assetMap.length(); i++) {
      (address key, ) = assetMap.at(i);
      assetMap.remove(key);
    }
  }
}
