# Aave Leveraged Swap

![App Screenshot](./screenshot.jpeg)

Dapp: [Aave-swap](https://aave-swap.oughtto.be)

Contract: [0xf2b08a65726b894b550f5c6cfc95576f8dec263f](https://polygonscan.com/address/0xf2b08a65726b894b550f5c6cfc95576f8dec263f)

This Dapp can help you engineer leveraged long/short positions with your [Aave](https://aave.com) collaterals. We assume that you understand Aave's borrow protocol and the incurred interests.

Currently, the Solidity contract is deployed on [Polygon](https://polygon.technology) network only, feel free to fork it on the Ethereum mainnet. If you'd like to understand how this contract calculates its numbers, checkout this [article](./math.md).

## Usage

### Leverage

Click the _CREATE A LEVERAGED POSITION_ button to create a position. Since we deposit a _Pair Token_ back, in most cases you can borrow more than the total of your collaterals with a not so risky _Health Factor_.

#### Create a long position for a crypto token

1. Choose a stable coin, i.e. Dai, USDC, as your **Target Token** ( _Loans_ )
2. Choose a token you want to long as your **Pair Token** ( _Collaterals_ )
3. Input the **amount** of Target Token you'd like to loan and watch the **Health Factor** accordingly.
4. Choose **the Borrow Rate Mode**, for some tokens a stable borrow rate is not available.
5. The **Fees** incurred include Aave's [flash loan](https://docs.aave.com/developers/v/2.0/guides/flash-loans) charge and the slippages when this contract swaps tokens for you. You may pay it by reducing the amount of your _Pair Token_ collaterals, or you can send in separately. Your existing collaterals WILL NOT change.
6. Choose the maximum slippage you can accept when this contract swaps tokens on behalf of you. Note that the slippage you choose applies to all token swaps. For some tokens, the [SushiSwap](https://sushi.com/) project that this contract relies on cannot offer a reasonable slippage, which can fail the transaction. We are working on a solution on it.
7. Click _Next_ and approve the delegation of this contract to borrow the _Target Token_ for the amount you chose on behalf of you.
8. Click _Submit_ to trigger the contract interaction with your crypto wallet.

#### Create a short position for a crypto token

1. Choose a token you want to short as your **Target Token** ( _Loans_ )
2. Choose a stable coin as your **Pair Token** ( _Collaterals_ )
3. Follow _Step 3_ and so on in the previous section. Remember that Target Token is the one you'd like its price to go down, and the opposite goes to the Pair Token. Stable coins are just the pair that pegs the price when you go only oneway. If properly selected, you can achieve a long&short position _simultaneously_.

### Deleverage

Deleverage can be done in a single transaction without introducing external liquidity.

1. Choose the loan you'd like to repay and click the _DELEVERAGE_ button.
2. Choose the amounts of your **Collaterals** to reduce for repaying your debt.
3. Choose the amount of **Target Token** you'd like to repay. Note that the amount must be less than or equal to the total value of your reduced collaterals. You have to maintain the _Health Factor_ above 1 as well.
4. Choose to **pay fees** from your reduced collaterals or from what you send in separately.
5. Choose the maximum slippage you can accept when this contract swaps tokens on behalf of you. Note that the slippage you choose applies to all token swaps.
6. Click _Next_. You need to approve all the **aTokens** of your reduced collaterals to transfer to this contract, so that it can withdraw them to pay for your debt.
7. Click _Submit_ to trigger the contract interaction with your crypto wallet.

**Note**: In both _leverage_ and _deleverage_, due to the variable slippages in token exchanges, the remaining tokens after repaying the flash loan, should there be any, will be transferred to the user account. This contract WILL NOT hold any tokens.

# Development

Since this contract relies on price oracles and token exchanges heavily, you need to [fork the mainnet](https://hardhat.org/hardhat-network/guides/mainnet-forking.html#mainnet-forking) for testing in order to get reliable token prices and slippages. To do this on Hardhat:

1. Set _INFURA_API_KEY_ env variable and it will be picked up in _hardhat.config.ts_. i.e.

```
{
  hardhat: {
    forking: {
      url:
        process.env.INFURA_API_KEY !== undefined
          ? `https://mainnet.infura.io/v3/${process.env.INFURA_API_KEY}`
          : "",
    },
  }
}
```

2. Run Hardhat node:

```shell
npx hardhat node --network hardhat
```

3. Run test cases:

```shell
npx hardhat test --network localhost
```

Or,

```shell
npx hardhat coverage --network localhost
```

## Contract error codes

| Code | Use case   | Description                                                                                                                                             |
| :--: | ---------- | ------------------------------------------------------------------------------------------------------------------------------------------------------- |
|  E1  | Leverage   | Collaterals are not enough to borrow the specified amount of target tokens.                                                                             |
|  E2  | Leverage   | User did not approve the borrow delegation for target tokens.                                                                                           |
|  E3  | Leverage   | Pair token cannot be collateral.                                                                                                                        |
|  E4  | Leverage   | Target token is not borrowable.                                                                                                                         |
|  E5  | Deleverage | Health factor is below 1.                                                                                                                               |
|  E6  | Deleverage | Duplicate entry in asset list.                                                                                                                          |
|  E7  | Deleverage | The lengths of asset list and amount list are not equal.                                                                                                |
|  E8  | Deleverage | At least one token in asset list cannot be collateral.                                                                                                  |
|  E9  | Deleverage | The reduced asset value cannot repay the target token.                                                                                                  |
| E10  | Deleverage | The reduced asset value exceeds what needed to repay the target token. \*Note that deleverage is not supposed to replace the withdraw function of Aave. |
| E11  | Deleverage | At least one token in asset list exceeds what user owns.                                                                                                |
| E12  | Deleverage | User did not approve at least one aToken in asset list transferring to contract.                                                                        |
| E13  | Deleverage | AToken transfer failed with unknown reason.                                                                                                             |
| E14  | Deleverage | The amount of variable debt of target token exceeds what user owns.                                                                                     |
| E15  | Deleverage | The amount of stable debt of target token exceeds what user owns.                                                                                       |
| E16  | General    | The fees sent in is not enough.                                                                                                                         |
| E17  | General    | Contract was not able to exchange tokens by the specified slippage.                                                                                     |
| E18  | General    | Contract multiplication operation overflowed.                                                                                                           |
| E19  | General    | Contract addition operation overflowed.                                                                                                                 |
| E20  | General    | Contract division operation was divided by zero.                                                                                                        |
| E21  | General    | Contract was called by an unknown function signature. (Fallback function is not allowed.)                                                               |
| E22  | General    | This contract function can be only called by _Aave Lending Pool_.                                                                                       |
