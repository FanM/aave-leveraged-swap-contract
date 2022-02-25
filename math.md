## Simple Maxium Borrow

From Aave protocol, every debt position needs to maintain its [health factor](https://docs.aave.com/risk/asset-risk/risk-parameters#health-factor) greater than 1, which means:

<img src="https://render.githubusercontent.com/render/math?math={\Large HF=\frac{Asset_{collat}}{Debt}=\frac{\sum_{i=1}^{k}(R_{liq}^{i}\cdot A_{i})}{Debt}\geq 1}" title="Health factor" />

<img src="https://render.githubusercontent.com/render/math?math={\large A_{i} , R_{liq}^{i}}" title="Loan constraints" /> are the *i*th asset value in ether and its [liquidation threshold](https://docs.aave.com/risk/asset-risk/risk-parameters#liquidation-threshold) respectively.

Therefore, if we'd like to borrow _L_ in value with some existing debt _D_, the following must be satisfied:

<img src="https://render.githubusercontent.com/render/math?math={\Large \sum_{i=1}^{k}(R_{liq}^{i}\cdot A_{i})-D_{exist}-L\geq 0} \space \space \space \textbf{(1)}" title="Simple maximum borrow" />

Or,

<img src="https://render.githubusercontent.com/render/math?math={\Large L\leq \sum_{i=1}^{k}(R_{liq}^{i}\cdot A_{i})-D_{exist}} \space \space \space \textbf{(2)}" title="Simple maximum borrow constraint" />

In practice, Aave has another constraint called [_Maximum Loan To Value_](https://docs.aave.com/risk/asset-risk/risk-parameters#loan-to-value) (LTV) on its assets, which is less than the liquidation threshold of that particular asset. This sets some safety buffer to protect the position from being liquidated in case the user borrows so much to drive his HF to 1. So the maximum he can borrow is:

<img src="https://render.githubusercontent.com/render/math?math={\Large L_{max}= \sum_{i=1}^{k}(R_{ltv}^{i}\cdot A_{i})-D_{exist}} \space \space \space \textbf{(3)}" title="Simple maximum borrow constraint" />

<img src="https://render.githubusercontent.com/render/math?math={\large R_{ltv}^{i}}" title="Loan to value" /> is the maximum _loan to value_ of the *i*th asset.

## Leverage

#### Borrow and Deposit Back

Sometimes people borrowing an asset just want to engineer some leveraged positions. For instance, they can short an asset by borrowing it, swapping it for a stable coin, then depositing the latter back. (A long position can be created just by swapping the asset pair just mentioned.) Suppose we borrow an asset with value _L_, exchange it to token _t_ with value _L'_ and deposit back. From **(1)**, we must satisfy:

<img src="https://render.githubusercontent.com/render/math?math={\Large  \sum_{i=1}^{k}(R_{liq}^{i}\cdot A_{i}) %2B R_{liq}^{t}\cdot L^{'} -D_{exist}-L\geq 0}" title="Maximum borrow by depositing back" />

Or, in practice:

<img src="https://render.githubusercontent.com/render/math?math={\Large \sum_{i=1}^{k}(R_{ltv}^{i}\cdot A_{i}) %2B R_{ltv}^{t}\cdot L^{'} -D_{exist}-L\geq 0} \space \space \space \textbf{(4)}" title="Maximum borrow by depositing back" />

If we don't consider the slippage during token swaps, which means _L_ = _L'_, the maximum we can end up borrowing is:

<img src="https://render.githubusercontent.com/render/math?math={\Large L_{max}=\frac{R_{ltv}^{A}\cdot A-D_{exist}}{1-R_{ltv}^{t}}} \space \space \space \textbf{(5)}" title="Maximum borrow by depositing back" />

Compared to **(3)**, suppose
<img src="https://render.githubusercontent.com/render/math?math={\large R_{ltv}^{t}}" title="Loan to value" /> is 80%, with the same amount of collaterals, in theory we can get 5 times of the original borrowing power, which is why we call it a leveraged position.

However, without increasing our collateral this can only be done by multiple borrow & deposit operations since each time the borrow limit is still enforced by **(3)**, not **(5)**.

#### Deposit, then Borrow

To achieve the aforementioned in a single operation, we need to reverse our process by acquiring some extra liquidity upfront. If someone can lend us _L'_ amount of some tokens to increase our collateral, then we will be able to borrow L amount of our chosen tokens from the liquidity pool. We repay that person by swapping our chosen tokens to the original tokens.

##### Flash Loan

Without asking a friend to do us this favor, we can utilize Aave's [flash loans](https://docs.aave.com/developers/guides/flash-loans) in this situation. It's not free. Consider **(4)**, the fee incurred for _L'_ amount is:

<img src="https://render.githubusercontent.com/render/math?math={\Large fee=R_{flash}\cdot L^{'}}" title="Flash loan fee" />

<img src="https://render.githubusercontent.com/render/math?math={\large R_{flash}}" title="Flash loan rate" /> is the rate of flash loan (0.09% currently in Aave).

Plus, we need to factor the lost due to the swap slippage in as well. Anyways, **(4)** has to be satisfied, or:

<img src="https://render.githubusercontent.com/render/math?math={\Large L \leq \sum_{i=1}^{k}(R_{ltv}^{i}\cdot A_{i})-D_{exist} %2B R_{ltv}^{t}\cdot L^{'}} \space \space \space \textbf{(6)}" title="maximum borrow with depositing back" />

Let's take the following two cases separately:

1. Pay fees using the collateral

  <img src="https://render.githubusercontent.com/render/math?math={\Large L\cdot(1-R_{slip})=(L^{'} %2B fee)}" title="lost in swap slippage" />
  Or,
  <img src="https://render.githubusercontent.com/render/math?math={\Large L^{'} = L \cdot \frac{1-R_{slip}}{1 %2B R_{flash}}} " title="lost in swap slippage" />
  So,
  <img src="https://render.githubusercontent.com/render/math?math={\Large L_{max} \leq \frac{(\sum_{i=1}^{k}(R_{ltv}^{i}\cdot A_{i})-D_{exist})\cdot(1 %2B R_{flash})}{1 %2B R_{flash}-R_{ltv}^{t}\cdot(1-R_{slip})}}" title="lost in swap slippage" />

2. Pay fees with extra ethers

  <img src="https://render.githubusercontent.com/render/math?math={\Large L^{'} = L\cdot(1-R_{slip})}" title="lost in swap slippage" />
  So,
  <img src="https://render.githubusercontent.com/render/math?math={\Large L_{max} \leq \frac{\sum_{i=1}^{k}(R_{ltv}^{i}\cdot A_{i})-D_{exist}}{1-R_{ltv}^{t}\cdot(1-R_{slip})}}" title="lost in swap slippage" />

Our health factor after those operations will be:

<img src="https://render.githubusercontent.com/render/math?math={\Large  HF=\frac{Asset_{collat}}{Debt}=\frac{Asset_{exist}%2BAsset_{\Delta} }{L%2B D_{exist}}=\frac{\sum_{i=1}^{k} (R_{liq}^{i}\cdot A_{i})%2BR_{liq}^{L}\cdot L^{'}}{L%2BD_{exist}}} \space \space \space \textbf{(7)}" title="Health factor" />

## Deleverage

A user can specify the amount of the debt asset she's willing to repay and a list of collaterals to swap out for that asset. The total collateral to be reduced is:

<img src="https://render.githubusercontent.com/render/math?math={\Large A^{'}=\sum_{i=1}^{m}A_{i}^{'}} \textbf{(8)}" />

<img src="https://render.githubusercontent.com/render/math?math={\large A_{i}^{'}}" title="Asset to reduce"/>is the reduced value\_ for the *i*th collateral.

Since Aave protocol doesn't allow a smart contract to withdraw collateral on behalf of a user. We still need to resort to flash loan to pay down the debt. First we flash-loan the same amount of debt token to repay the debt our user wants to reduce, which incurs fee:

<img src="https://render.githubusercontent.com/render/math?math={\Large fee=R_{flash}\cdot D_{repay}}" title="Flash loan fee" />

Secondly, we swap the reduced collaterals to the debt token to repay the flash loan. Consider the slippage, the amount we got after the swap will be:

<img src="https://render.githubusercontent.com/render/math?math={\Large \Delta=(1-R_{slip})\cdot A^{'}} \space \space \textbf{(9)}" title="Collateral reduced after swap" />

And make sure we verify in either case:

1. Pay fees using the collateral

  <img src="https://render.githubusercontent.com/render/math?math={\Large \Delta\geq D_{repay} %2B fee}" title="Fee constraint" />

2. Pay fees with extra ethers

  <img src="https://render.githubusercontent.com/render/math?math={\Large \Delta\geq D_{repay}}" title="Fee constraint" />

Our new debt position:

<img src="https://render.githubusercontent.com/render/math?math={\Large Debt=D_{exist}-D_{repay}} \space \space \space \textbf{(10)}" title="New debt position" />

New health factor:

<img src="https://render.githubusercontent.com/render/math?math={\Large HF=\frac{Asset_{collat}}{Debt}=\frac{\sum_{i=1}^{k}R_{liq}^{i}\cdot A_{i} -\sum_{i=1}^{m}R_{liq}^{i}\cdot A_{i}^{'}}{D_{exist}-D_{repay}}} \space \space \space \textbf{(11)}" title="Health factor" />
