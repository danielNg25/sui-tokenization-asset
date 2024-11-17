module tokenization::tokenization {
    use tokenization::revenue_registry::{Self, RevenueRegistry, OperatorCap};
    use tokenization::tokenized_asset::{Self, TokenizedAsset, AssetCap, AssetMetadata};

    use std::string::{String};
    use std::ascii;
    use sui::types;
    use sui::coin::{Coin};

    const EBadWitness: u64 = 1;
    const EEmptyVector: u64 = 2;


    /// Capability that is issued to the one deploying the contract.
    /// Allows access to the publisher.
    public struct MinterCap has key, store { id: UID }

    /// Creates a MinterCap and sends it to the sender.
    fun init(ctx: &mut TxContext) {
        transfer::transfer(MinterCap {
            id: object::new(ctx)
        }, tx_context::sender(ctx))
    }
    
    public fun new_asset_<T: drop>(
        witness: T,
        total_supply: u64,
        symbol: ascii::String,
        name: String,
        description: String,
        icon_url: Option<vector<u8>>,
        burnable: bool,
        ctx: &mut TxContext
    ): (AssetCap<T>, AssetMetadata<T>, RevenueRegistry<T>, OperatorCap<T>) {
        assert!(types::is_one_time_witness(&witness), EBadWitness);

        let (asset_cap, asset_metadata) = tokenized_asset::new_asset(
            witness,
            total_supply,
            symbol,
            name,
            description,
            icon_url,
            burnable,
            ctx
        );

        let (revenue_registry, operator_cap) = revenue_registry::create_revenue_registry<T>(ctx);


        (asset_cap, asset_metadata, revenue_registry, operator_cap)
    }

    public fun mint<T>(
        asset_cap: &mut AssetCap<T>,
        _: &MinterCap,
        revenue_registry: &mut RevenueRegistry<T>,
        value: u64,
        ctx: &mut TxContext
    ): TokenizedAsset<T>{
        let tokenized_asset = asset_cap.mint(value, ctx);
        revenue_registry.create(&tokenized_asset, ctx);

        tokenized_asset
    }

    public fun split<T>(
        revenue_registry: &mut RevenueRegistry<T>,
        tokenized_asset: &mut TokenizedAsset<T>,
        value: u64,
        ctx: &mut TxContext
    ): TokenizedAsset<T>{
        revenue_registry.decrease(tokenized_asset, value);
        let new_tokenized_asset = tokenized_asset::split(tokenized_asset, value, ctx);
        revenue_registry.create(&new_tokenized_asset, ctx);

        new_tokenized_asset
    }

    public fun join<T>(
        revenue_registry: &mut RevenueRegistry<T>,
        tokenized_asset: &mut TokenizedAsset<T>,
        other: TokenizedAsset<T>
    ): ID{
        revenue_registry.destroy(&other);
        revenue_registry.increase(tokenized_asset, other.value());
        let id = tokenized_asset.join(other);

        id
    }

    public fun burn<T>(
        cap: &mut AssetCap<T>,
        _: &MinterCap,
        revenue_registry: &mut RevenueRegistry<T>,
        tokenized_asset: TokenizedAsset<T>
    ){
        revenue_registry.destroy(&tokenized_asset);
        cap.burn(tokenized_asset);
    }

    public fun deposit_revenue<T, R>(
        revenue_registry: &mut RevenueRegistry<T>,
        operator_cap: &OperatorCap<T>,
        asset_cap: &AssetCap<T>,
        revenue: Coin<R>,
        ctx: &mut TxContext,
    ) {
        revenue_registry.deposit_revenue(operator_cap, asset_cap, revenue, ctx);
    }

    public fun claim_revenue<T, R>(
        revenue_registry: &mut RevenueRegistry<T>,
        tokenized_asset: &TokenizedAsset<T>,
        ctx: &mut TxContext,
    ): Coin<R> {
        revenue_registry.claim_revenue(tokenized_asset, ctx)
    }

    public fun claim_revenue_multiple<T, R>(
        revenue_registry: &mut RevenueRegistry<T>,
        tokenized_assets: &vector<TokenizedAsset<T>>,
        ctx: &mut TxContext,
    ): Coin<R> {
        let asset_length = tokenized_assets.length();
        assert!(asset_length > 0, EEmptyVector);
        let mut revenue = revenue_registry.claim_revenue<T, R>(tokenized_assets.borrow(0), ctx);
        
        let mut i = 1;
        while (i < asset_length) {
            revenue.join(revenue_registry.claim_revenue<T, R>(tokenized_assets.borrow(i), ctx));
            i = i + 1;
        };

        revenue
    }

    #[test_only]
    public fun init_for_testing(ctx: &mut TxContext) {
        init(ctx);
    }
}