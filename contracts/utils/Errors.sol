// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

library Errors {
  string public constant LEVERAGE_COLLATERAL_NOT_ENOUGH = "E1";
  string public constant LEVERAGE_USER_DID_NOT_DELEGATE_BORROW = "E2";
  string public constant LEVERAGE_PAIR_TOKEN_NOT_COLLATERABLE = "E3";
  string public constant LEVERAGE_TARGET_TOKEN_NOT_BORROWABLE = "E4";
  string public constant DELEVERAGE_HEALTH_FACTOR_BELOW_ONE = "E5";
  string public constant DELEVERAGE_DUPLICATE_ASSET_ENTRY = "E6";
  string public constant DELEVERAGE_MISMATCHED_ASSETS_AND_AMOUNTS = "E7";
  string public constant DELEVERAGE_ASSET_TOKEN_CANNOT_BE_COLLATERAL = "E8";
  string public constant DELEVERAGE_REDUCED_ASSET_NOT_ENOUGH = "E9";
  string public constant DELEVERAGE_REDUCED_ASSET_EXCCEED_NEEDED = "E10";
  string public constant DELEVERAGE_ATOKEN_SPECIFIED_EXCEEDS_OWNED = "E11";
  string public constant DELEVERAGE_USER_DID_NOT_APPROVE_ATOKEN_TRANSFER =
    "E12";
  string public constant DELEVERAGE_ATOKEN_TRANSFER_FAILED_WITH_UNKNOWN_REASON =
    "E13";
  string public constant DELEVERAGE_VARIABLE_DEBT_SPECIFIED_EXCEEDS_OWNED =
    "E14";
  string public constant DELEVERAGE_STABLE_DEBT_SPECIFIED_EXCEEDS_OWNED = "E15";
  string public constant OPS_FLASH_LOAN_FEE_NOT_ENOUGH = "E16";
  string public constant OPS_NOT_ABLE_TO_EXCHANGE_BY_SPECIFIED_SLIPPAGE = "E17";
  string public constant MATH_MULTIPLICATION_OVERFLOW = "E18";
  string public constant MATH_ADDITION_OVERFLOW = "E19";
  string public constant MATH_DIVISION_BY_ZERO = "E20";
  string public constant CONTRACT_FALLBACK_NOT_ALLOWED = "E21";
  string public constant CONTRACT_ONLY_CALLED_BY_LENDING_POOL = "E22";
}
