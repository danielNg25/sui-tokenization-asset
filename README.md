# sui-tokenization

⚠️ **Note:** Instead of using `token_id` for determine unique identifiers between unique assets, we use move structs as one time witness for better move practice. The asset identifiers will be like this `TokenizedAsset<TOKEN>` where `TOKEN` is witness.

# Key Features

## Access Control

-   `MinterCap`: an owned object allow owner to create new asset on the plaform, mint/burn `TokenizedAsset<TOKEN>`
-   `OperatorCap<TOKEN>`: an owned object allow owner to deposit revenue asset for `TokenizedAsset<TOKEN>` type

## Token Minting

-   `MinterCap` owner can create new asset with `new_asset` function.
-   Mint/Burn token from specific asset using `mint` and `burn` function. Token is not minted in `new_asset` function. Minted amount can not exceed `total_supply`.

```rust
public fun new_asset_<T: drop>(
    witness: T,
    _minter_cap: &MinterCap,
    total_supply: u64,
    symbol: ascii::String,
    name: String,
    description: String,
    icon_url: Option<vector<u8>>,
    burnable: bool,
    ctx: &mut TxContext
)
```

## Revenue Deposit

-   `OperatorCap` owner are able to deposit revenue coin for specific asset type. Revenue can be any kind of `Coin<T>` (maximum to 1024 type of revenue coin due to sui move's limit vector size)

```rust
public fun deposit_revenue<T, R>(
    revenue_registry: &mut RevenueRegistry<T>,
    operator_cap: &OperatorCap<T>,
    asset_cap: &AssetCap<T>,
    revenue: Coin<R>,
    ctx: &mut TxContext,
)
```

-   Deposited revenue are recorded in:

    -   `RevenueRegistry`: list of deposited revenue coin and revenue accumulated per unit of token
    -   `CoinVault`: remainning unclaimed revenue

```rust
public struct RevenueRegistry<phantom T> has key, store {
    id: UID,
    revenue_coins: VecSet<TypeName>,
    vault_acc_balances_per_share: VecMap<TypeName, u256>
}

public struct CoinVault<phantom T> has key, store {
    id: UID,
    remaining_revenue: Balance<T>
}
```

## Revenue Withdrawal

Revenue calculate are inspired by SushiSwap's MasterChef:

-   Code: https://github.com/sushiswap/masterchef
-   Explaination: https://dev.to/heymarkkop/understanding-sushiswaps-masterchef-staking-rewards-1m6f

The main thing is tracking user's balance (SushiSwap requires user to stake their token) and reward debt per token (see more about debt in above links).

Move is not account based like EVM, it's object based (each user can have multiple `TokenizedAsset`/`Coin` and each `TokenizedAsset`/`Coin` can have different balance), so that instead tracking user's balance, we'll tracking `TokenizedAsset` object's balance and it's reward debt in this object:

```rust
public struct AssetRevenueDebt has key, store {
    id: UID,
    asset_id: ID,
    asset_revenue_debts: VecMap<TypeName, Int> // mapping from revenue token type to debt
}
```

-   `asset_revenue_debts` will be update whenever an action that update `TokenizedAsset`'s balance (`mint`, `burn`, `join`, `split`).

-   `burn` action requires that `TokenizedAsset` object to be claimed all pending revenue to prevent loss of unclaimed revenue forever.

# Testnet Deployment Address

## Tokenization package:

| Name      | ID                                                                 |
| --------- | ------------------------------------------------------------------ |
| Package   | 0x0b3eb86c7ca37866d8bff495b88fd72d63086a79c132cab12f616aa9b1c002ce |
| MinterCap | 0x40a768f0775a5c6ce06a36ecab1e15b4530f702f724ee2433af715b353053992 |

## Test Asset

| Name            | ID                                                                 |
| --------------- | ------------------------------------------------------------------ |
| RevenueRegistry | 0x3723bab9cf400f9badd5471936dae16c538693e062c5c975410b0e253a818d90 |
| AssetMetadata   | 0x0b3eb86c7ca37866d8bff495b88fd72d63086a79c132cab12f616aa9b1c002ce |
| OperatorCap     | 0x6a509985f7d7b51a7016a1e89428c816c51f452177479c1138a6b288e207197d |
| AssetCap        | 0xafb4353ea99e5850314f3196a02c7fb4c99d2767344c502b3941fa4baef9c56d |
