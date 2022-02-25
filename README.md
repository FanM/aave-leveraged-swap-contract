# Aave Leveraged Swap

This Dapp can help you engineer leveraged long/short positions with your [Aave](https://aave.com) collaterals. We assume that you understand Aave's borrow protocol and the incurred interests.

Currently, the [solidity contract](https://polygonscan.com/address/0xf2b08a65726b894b550f5c6cfc95576f8dec263f#code) is deployed on Polygon network only, feel free to fork it on the Ethereum mainnet. If you'd like to understand how this contract calculates its numbers, checkout this [article](./math.md).

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
3. Follow the Step 3 and so on in the previous section. Remember that Target Token is the one you'd like its price to go down, the opposite goes to the Pair Token. Stable coins are just the pair that pegs the price. If properly selected, you can achieve a long/short position simultaneously.

### Deleverage

Deleverage can be done in a single transaction without introducing external liquidity.

1. Choose the loan you'd like to repay and click the _DELEVERAGE_ button.
2. Choose the amounts of your **Collaterals** to reduce for repaying your debt.
3. Choose the amount of **Target Token** you'd like to repay. Note that the amount must be less than or equal to the total value of your reduced collaterals. You have to maintain the _Health Factor_ above 1 as well.
4. Choose to **pay fees** from your reduced collaterals or from what you send in separately.
5. Choose the maximum slippage you can accept when this contract swaps tokens on behalf of you. Note that the slippage you choose applies to all token swaps.
6. Click _Next_. You need to approve all the **aTokens** of your reduced collaterals to transfer to this contract, so that it can withdraw them to pay for your debt.
7. Click _Submit_ to trigger the contract interaction with your crypto wallet.

# Development

Since this contract relies on price oracles and token exchanges heavily, you need to [fork the mainnet](https://hardhat.org/hardhat-network/guides/mainnet-forking.html#mainnet-forking) for testing in order to get reliable token prices and slippages. To do this on Hardhat:

1. Set _INFURA_API_KEY_ env variable and it will be picked up in _hardhat.config.ts_. i.e.

```json
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
