//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./interfaces/IFlashLoanReceiver.sol";
import "./interfaces/ILendingPool.sol";
import "./AaveLeveragedSwapBase.sol";
import "./utils/PercentageMath.sol";
import "./utils/WadRayMath.sol";
import "./utils/Errors.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";

contract AaveLeveragedSwapManager is
  IFlashLoanReceiver,
  ReentrancyGuard,
  Initializable,
  AaveLeveragedSwapBase
{
  using SafeERC20 for IERC20;
  using WadRayMath for uint256;
  using PercentageMath for uint256;
  using EnumerableMap for EnumerableMap.AddressToUintsMap;

  function initialize(
    address _addressProvider,
    address _sushiRouter,
    address _nativeETH
  ) external initializer {
    ADDRESSES_PROVIDER = ILendingPoolAddressesProvider(_addressProvider);
    LENDING_POOL = ILendingPool(ADDRESSES_PROVIDER.getLendingPool());
    DATA_PROVIDER = IProtocolDataProvider(
      ADDRESSES_PROVIDER.getAddress(PROTOCOL_DATA_PROVIDER_ID)
    );
    PRICE_ORACLE = IPriceOracleGetter(ADDRESSES_PROVIDER.getPriceOracle());
    SUSHI_ROUTER = IUniswapV2Router02(_sushiRouter);
    NATIVE_ETH = _nativeETH;
  }

  /**
   * @dev execute a leveraged swap. If fee wasn't sent in, it will be deducted from collaterals
   * @param _targetToken The token that will be borrowed
   * @param _targetAmount The amount of the token
   * @param _pairToken The token that will be swapped to and deposited
   * @param _rateMode The interest rate mode of the debt the user wants to repay: 1 for Stable, 2 for Variable
   * @param _slippage The max slippage allowed during swap
   */
  function swapPreapprovedAssets(
    TokenInfo memory _targetToken,
    uint _targetAmount,
    TokenInfo memory _pairToken,
    uint _rateMode,
    uint _slippage
  ) external payable override nonReentrant {
    vars.user = msg.sender;
    vars.targetToken = _targetToken;
    vars.targetTokenAmount = _targetAmount;
    vars.pairToken = _pairToken;
    vars.borrowRateMode = _rateMode;
    vars.slippage = _slippage;

    SwapVars memory swapVars = checkAndCalculateSwapVars(
      _targetToken,
      _targetAmount,
      _pairToken,
      _slippage,
      msg.value == 0
    );
    require(
      swapVars.loanETH <= swapVars.maxLoanETH,
      Errors.LEVERAGE_COLLATERAL_NOT_ENOUGH
    );

    vars.loanETH = swapVars.loanETH;
    vars.feeETH = swapVars.feeETH;

    uint flashLoanETH = swapVars.flashLoanETH;
    if (msg.value > 0) {
      // uses the native token sent to pay the fees
      _ensureValueSentCanCoverFees(msg.value);
    }
    // calculates the amount we need to flash loan in pairToken
    vars.pairTokenAmount = convertEthToTokenAmount(
      flashLoanETH,
      vars.pairToken
    );

    _doFlashLoan(_pairToken.tokenAddress, vars.pairTokenAmount);

    cleanUpAfterSwap();
  }

  /**
   * @dev deleverage caller's debt position by repaying debt from collaterals. If fee wasn't sent in, it will be deducted from collaterals
   * @param _collaterals The list of collaterals in caller's portfolio
   * @param _collateralAmounts The list of collateral amounts that will be reduced
   * @param _targetToken The token that will be repayed
   * @param _targetAmount The amount of token that will be repayed
   * @param _rateMode The interest rate mode of the debt the user wants to repay: 1 for Stable, 2 for Variable
   * @param _slippage The max slippage allowed during swap
   */
  function repayDebt(
    TokenInfo[] calldata _collaterals,
    uint256[] calldata _collateralAmounts,
    TokenInfo memory _targetToken,
    uint _targetAmount,
    uint _rateMode,
    uint _slippage
  ) external payable override nonReentrant {
    // Intuitively, deleveraging can be realized by withdrawing user's collaterals
    // and repaying her debt positions. However, Aave protocol doesn't allow
    // contract to withdraw on behalf of user. So our strategy still relies on
    // using flash loan to pay down user's debt, then transferring her aTokens
    // to contract for repaying the loan.
    vars.user = msg.sender;
    vars.targetToken = _targetToken;
    vars.targetTokenAmount = _targetAmount;
    vars.borrowRateMode = _rateMode;
    vars.slippage = _slippage;

    // calcuates how much of collaterals we can reduce
    RepayVars memory repayVars = checkAndCalculateRepayVars(
      _collaterals,
      _collateralAmounts,
      _targetToken,
      _targetAmount,
      _rateMode,
      _slippage,
      msg.value == 0
    );

    require(
      repayVars.totalCollateralReducedETH >= repayVars.loanETH,
      Errors.DELEVERAGE_REDUCED_ASSET_NOT_ENOUGH
    );
    require(
      repayVars.expectedHealthFactor > WadRayMath.WAD,
      Errors.DELEVERAGE_HEALTH_FACTOR_BELOW_ONE
    );

    uint[] memory reducedCollateralValues = repayVars.reducedCollateralValues;
    vars.feeETH = repayVars.feeETH;

    // make sure we have a clean map
    assert(assetMap.length() == 0);
    for (uint i = 0; i < _collaterals.length; i++) {
      uint[2] memory values = [
        _collateralAmounts[i],
        reducedCollateralValues[i]
      ];
      require(
        assetMap.set(_collaterals[i].tokenAddress, values),
        Errors.DELEVERAGE_DUPLICATE_ASSET_ENTRY
      );
    }

    if (msg.value > 0) {
      // uses the native token sent in to pay the fees
      _ensureValueSentCanCoverFees(msg.value);
    }

    _doFlashLoan(_targetToken.tokenAddress, _targetAmount);

    cleanUpAfterSwap();
  }

  /**
   * This function is called after your contract has received the flash loaned amount.
   * So it allows reentrancy by design. You need to make sure the LendingPool calling
   * it behaves faithfully.
   */
  function executeOperation(
    address[] calldata _assets,
    uint256[] calldata _amounts,
    uint256[] calldata _premiums,
    address _initiator,
    bytes calldata // params
  ) external override onlyLendingPool returns (bool) {
    // ensures this function is indeed called by the lending pool with
    // correct arguments.
    assert(_assets.length == 1 && _initiator == address(this));
    if (_assets[0] == vars.pairToken.tokenAddress) {
      assert(_amounts[0] == vars.pairTokenAmount);
      return _handleLeverage(vars.pairToken, _amounts[0], _premiums[0]);
    } else {
      assert(
        _assets[0] == vars.targetToken.tokenAddress &&
          _amounts[0] == vars.targetTokenAmount
      );
      return _handleDeleverage(vars.targetToken, _amounts[0], _premiums[0]);
    }
  }

  fallback() external {
    revert(Errors.CONTRACT_FALLBACK_NOT_ALLOWED);
  }

  function _ensureValueSentCanCoverFees(uint _value) private {
    // converts the native token value to ETH
    // factors in the swap slippage and
    uint wethAmount = PRICE_ORACLE.getAssetPrice(NATIVE_ETH).wadMul(_value);
    // verifies that its value is enough to cover the fees
    require(wethAmount >= vars.feeETH, Errors.OPS_FLASH_LOAN_FEE_NOT_ENOUGH);
    vars.feeTokenAmount = _value;
  }

  function _doFlashLoan(address _asset, uint _amount) private {
    address[] memory flashLoanAssets = new address[](1);
    flashLoanAssets[0] = _asset;
    uint[] memory flashLoanAmounts = new uint[](1);
    flashLoanAmounts[0] = _amount;
    uint[] memory flashLoanModes = new uint[](1);
    flashLoanModes[0] = 0; // 0 = no debt
    LENDING_POOL.flashLoan(
      address(this), // receiverAddress
      flashLoanAssets,
      flashLoanAmounts,
      flashLoanModes,
      address(this), // onBehalfOf
      bytes(""), // params
      0 // referralCode
    );
  }

  function _handleLeverage(
    TokenInfo memory _pairToken,
    uint _pairTokenAmount,
    uint _premium
  ) private returns (bool) {
    // deposits the flash loan to increase user's collateral
    IERC20(_pairToken.tokenAddress).safeApprove(
      address(LENDING_POOL),
      _pairTokenAmount.wadToDecimals(_pairToken.decimals)
    );
    LENDING_POOL.deposit(
      _pairToken.tokenAddress,
      _pairTokenAmount,
      vars.user, /*onBehalfOf*/
      0 /*referralCode*/
    );

    // borrows targetToken and sends the amount to this contract,
    // with the debt being incurred by user.
    // user has to delegate vars.targetTokenAmount of targetToken credit
    // to this contract in advance
    try
      LENDING_POOL.borrow(
        vars.targetToken.tokenAddress,
        vars.targetTokenAmount,
        vars.borrowRateMode,
        0, /*referralCode*/
        vars.user /*debt incurred to*/
      )
    {} catch Error(
      string memory /*reason*/
    ) {
      revert(Errors.LEVERAGE_USER_DID_NOT_DELEGATE_BORROW);
    }

    // swaps the borrowed targetToken to pay for flash loan
    uint pairTokenAmount = approveAndSwapExactTokensForTokens(
      vars.targetToken,
      vars.targetTokenAmount,
      vars.pairToken,
      convertEthToTokenAmount(
        vars.loanETH.percentMul(
          PercentageMath.PERCENTAGE_FACTOR - vars.slippage
        ),
        vars.pairToken
      ),
      address(this) /*onBehalfOf*/
    );

    if (vars.feeTokenAmount > 0) {
      // user uses wethToken to cover the fees
      // swap native eth to pay fees
      pairTokenAmount += swapExactETHForTokens(
        vars.feeTokenAmount,
        vars.pairToken,
        convertEthToTokenAmount(vars.feeETH, vars.pairToken).percentMul(
          PercentageMath.PERCENTAGE_FACTOR - vars.slippage
        ),
        address(this) /*onBehalfOf*/
      );
    }

    uint amountOwing = _pairTokenAmount + _premium;
    assert(pairTokenAmount >= amountOwing);
    uint remainPairTokenAmount;
    unchecked {
      remainPairTokenAmount = pairTokenAmount - amountOwing;
    }

    // approves the LendingPool contract allowance to *pull* the owed amount
    IERC20(_pairToken.tokenAddress).safeApprove(
      address(LENDING_POOL),
      amountOwing.wadToDecimals(_pairToken.decimals)
    );

    // transfers the remaining pairToken to the user's account if there is any
    IERC20(_pairToken.tokenAddress).safeTransfer(
      vars.user,
      remainPairTokenAmount.wadToDecimals(_pairToken.decimals)
    );

    emit Leverage(
      vars.targetToken.tokenAddress,
      _pairToken.tokenAddress,
      vars.user,
      vars.targetTokenAmount,
      vars.borrowRateMode,
      vars.slippage,
      remainPairTokenAmount
    );

    return true;
  }

  function _handleDeleverage(
    TokenInfo memory _targetToken,
    uint _targetAmount,
    uint _premium
  ) private returns (bool) {
    // repays the user's debt with the flash loaned targetToken
    IERC20(_targetToken.tokenAddress).safeApprove(
      address(LENDING_POOL),
      _targetAmount.wadToDecimals(_targetToken.decimals)
    );
    LENDING_POOL.repay(
      _targetToken.tokenAddress,
      _targetAmount,
      vars.borrowRateMode,
      vars.user /*onBehalfOf*/
    );

    uint targetTokenAmountConverted;
    // depends on caller to check there's no duplicate entries
    for (uint i = 0; i < assetMap.length(); i++) {
      (address asset, uint[2] memory values) = assetMap.at(i);
      TokenInfo memory assetInfo = getTokenInfo(asset);

      // transfers aToken to this contract for withdraw
      transferUserATokenToContract(
        assetInfo,
        values[0], /*asset amount*/
        vars.user
      );

      // withdraws the asset to this contract
      LENDING_POOL.withdraw(
        asset,
        values[0],
        address(this) /*to address*/
      );

      // swaps the asset to targetToken
      targetTokenAmountConverted += approveAndSwapExactTokensForTokens(
        assetInfo,
        values[0],
        vars.targetToken,
        convertEthToTokenAmount(
          values[1], /*asset value ETH*/
          vars.targetToken
        ).percentMul(PercentageMath.PERCENTAGE_FACTOR - vars.slippage),
        address(this) /*onBehalfOf*/
      );
    }

    if (vars.feeTokenAmount > 0) {
      // swap native eth to pay fees
      targetTokenAmountConverted += swapExactETHForTokens(
        vars.feeTokenAmount,
        vars.targetToken,
        convertEthToTokenAmount(vars.feeETH, vars.targetToken).percentMul(
          PercentageMath.PERCENTAGE_FACTOR - vars.slippage
        ),
        address(this) /*onBehalfOf*/
      );
    }

    uint amountOwing = _targetAmount + _premium;
    assert(targetTokenAmountConverted >= amountOwing);
    uint remainingTargetToken;
    unchecked {
      remainingTargetToken = targetTokenAmountConverted - amountOwing;
    }
    // Approve the LendingPool contract allowance to *pull* the owed amount
    IERC20(_targetToken.tokenAddress).safeApprove(
      address(LENDING_POOL),
      amountOwing.wadToDecimals(_targetToken.decimals)
    );

    // transfer the remaining to user if there's any
    IERC20(_targetToken.tokenAddress).safeTransfer(
      vars.user,
      remainingTargetToken.wadToDecimals(_targetToken.decimals)
    );

    emit Deleverage(
      _targetToken.tokenAddress,
      vars.user,
      _targetAmount,
      vars.borrowRateMode,
      vars.slippage,
      remainingTargetToken
    );

    return true;
  }
}
