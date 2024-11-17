module tokenization::revenue_registry {
    use sui::vec_set::{Self, VecSet};
    use sui::vec_map::{Self, VecMap};
    use sui::dynamic_object_field;
    use sui::coin::{Self, Coin};
    use sui::balance::{Self, Balance};
    use sui::event;

    use std::type_name::{Self, TypeName};
    use std::ascii::{String};

    use tokenization::tokenized_asset::{AssetCap, TokenizedAsset};
    use tokenization::int::{Self, Int};

    const PRECISION: u256 = 1_000_000_000;

    const EDestroyAssetWithPendingRevenue: u64 = 1;
    const EInvalidRevenueCoinType: u64 = 2;
    const ENothingToClaim: u64 = 3;

    public struct RevenueRegistry<phantom T> has key, store {
        id: UID,
        revenue_coins: VecSet<TypeName>,
        vault_acc_balances_per_share: VecMap<TypeName, u256>
    }

    public struct AssetRevenueDebt has key, store {
        id: UID,
        asset_id: ID,
        asset_revenue_debts: VecMap<TypeName, Int> // mapping from revenue token type to debt
    }

    public struct CoinVault<phantom T> has key, store {
        id: UID,
        remaining_revenue: Balance<T>
    }

    /// Allows the owner to deposit revenue assets.
    public struct OperatorCap<phantom T> has key, store { id: UID }

    public struct RevenueDepositedEvent has copy, drop {
        asset_type: String,
        revenue_coin_type: String,
        revenue: u64
    }

    public struct RevenueClaimedEvent has copy, drop {
        asset_id: ID,
        asset_type: String,
        revenue_coin_type: String,
        revenue: u64
    }
    
    public fun get_revenue_registry<T>(
        revenue_registry: &RevenueRegistry<T>
    ): (VecSet<TypeName>, VecMap<TypeName, u256>) {
        (revenue_registry.revenue_coins, revenue_registry.vault_acc_balances_per_share)
    }

    public fun get_asset_revenue_debts<T>(
        revenue_registry: &RevenueRegistry<T>,
        tokenized_asset: &TokenizedAsset<T>
    ): VecMap<TypeName, Int> {
        let asset_revenue_debts_obj = dynamic_object_field::borrow<ID, AssetRevenueDebt>(&revenue_registry.id, object::id(tokenized_asset));
        asset_revenue_debts_obj.asset_revenue_debts
    }

    public fun remaining_revenue<T, R>(
        revenue_registry: &RevenueRegistry<T>,
    ): u64 {
        let revenue_coin_type = type_name::get<R>();
        assert!(revenue_registry.revenue_coins.contains(&revenue_coin_type), EInvalidRevenueCoinType);
        let coin_vault = dynamic_object_field::borrow<TypeName, CoinVault<R>>(&revenue_registry.id, revenue_coin_type);
        coin_vault.remaining_revenue.value()
    }

    public(package) fun create_revenue_registry<T>(
        ctx: &mut TxContext
    ): (RevenueRegistry<T>, OperatorCap<T>) {
        let revenue_registry =  RevenueRegistry<T>{
            id: object::new(ctx),
            revenue_coins: vec_set::empty(),
            vault_acc_balances_per_share: vec_map::empty()
        };

        let operator_cap = OperatorCap<T>{
            id: object::new(ctx)
        };

        (revenue_registry, operator_cap)
    }

    public(package) fun deposit_revenue<T, R>(
        revenue_registry: &mut RevenueRegistry<T>,
        _: &OperatorCap<T>,
        asset_cap: &AssetCap<T>,
        revenue: Coin<R>,
        ctx: &mut TxContext,
    ) {
        let revenue_coin_type = type_name::get<R>();
        if (!revenue_registry.revenue_coins.contains(&revenue_coin_type)) {
            revenue_registry.revenue_coins.insert(revenue_coin_type);
            let coin_vault = CoinVault<R>{
                id: object::new(ctx),
                remaining_revenue: balance::zero()
            };

            dynamic_object_field::add(&mut revenue_registry.id, revenue_coin_type, coin_vault);
            revenue_registry.vault_acc_balances_per_share.insert(revenue_coin_type, 0);
        };

        let amount = revenue.value();
        let vault_acc_balances_per_share = revenue_registry.vault_acc_balances_per_share.get_mut(&revenue_coin_type);
        *vault_acc_balances_per_share = *vault_acc_balances_per_share + (amount as u256) * PRECISION / (asset_cap.supply() as u256);

        let coin_vault = dynamic_object_field::borrow_mut<TypeName, CoinVault<R>>(&mut revenue_registry.id, revenue_coin_type);
        coin_vault.remaining_revenue.join(revenue.into_balance());   

        event::emit(RevenueDepositedEvent {
            asset_type: type_name::get<T>().into_string(),
            revenue_coin_type: type_name::get<R>().into_string(),
            revenue: amount
        })
    }

    public(package) fun create<T>(
        revenue_registry: &mut RevenueRegistry<T>,
        tokenized_asset: &TokenizedAsset<T>,
        ctx: &mut TxContext
    ) {
        let mut asset_revenue_debts_obj = AssetRevenueDebt{
            id: object::new(ctx),
            asset_id: object::id(tokenized_asset),
            asset_revenue_debts: vec_map::empty()
        };
        let balance = tokenized_asset.value();
        let revenue_coins = revenue_registry.revenue_coins.keys();
        let revenue_coins_len = revenue_coins.length();
        let mut i = 0;
        while(i < revenue_coins_len) {
            let revenue_coin_type = revenue_coins.borrow(i);
            let vault_acc_balances_per_share = revenue_registry.vault_acc_balances_per_share.get(revenue_coin_type);
            asset_revenue_debts_obj.asset_revenue_debts.insert(*revenue_coin_type, int::from_u256(*vault_acc_balances_per_share * (balance as u256) / PRECISION));
            i = i + 1;
        };
        dynamic_object_field::add(&mut revenue_registry.id, object::id(tokenized_asset), asset_revenue_debts_obj);
    }
     
    // When split or join balance from one TokenizedAsset object to another TokenizedAsset object
    // 1. update the rewardDebt of the (to) another user to accBalancePerShare * userAmount - pending
    // 2. update the rewardDebt of the (from) user to accBalancePerShare * userAmount - pending
    public(package) fun increase<T>(
        revenue_registry: &mut RevenueRegistry<T>,
        tokenized_asset: &TokenizedAsset<T>,
        amount: u64
    ) {
        let balance = tokenized_asset.value();

        let revenue_coins = revenue_registry.revenue_coins.keys();
        let revenue_coins_len = revenue_coins.length();
        let mut i = 0;
        while(i < revenue_coins_len) {
            let revenue_coin_type = revenue_coins.borrow(i);
            let vault_acc_balances_per_share = revenue_registry.vault_acc_balances_per_share.get(revenue_coin_type);
            let pending = claimable_revenue_(revenue_registry, revenue_coin_type, tokenized_asset);
            let asset_revenue_debts_obj = dynamic_object_field::borrow_mut<ID, AssetRevenueDebt>(&mut revenue_registry.id, object::id(tokenized_asset));
            if (!asset_revenue_debts_obj.asset_revenue_debts.contains(revenue_coin_type)) {
                asset_revenue_debts_obj.asset_revenue_debts.insert(*revenue_coin_type, int::zero());
            };
            *asset_revenue_debts_obj.asset_revenue_debts.get_mut(revenue_coin_type) = int::from_u256(*vault_acc_balances_per_share * ((balance + amount) as u256) / PRECISION - (pending as u256));

            i = i + 1;
        }
    }

    public(package) fun decrease<T>(
        revenue_registry: &mut RevenueRegistry<T>,
        tokenized_asset: &TokenizedAsset<T>,
        amount: u64
    ) {
        let balance = tokenized_asset.value();

        let revenue_coins = revenue_registry.revenue_coins.keys();
        let revenue_coins_len = revenue_coins.length();
        let mut i = 0;
        while(i < revenue_coins_len) {
            let revenue_coin_type = revenue_coins.borrow(i);
            let vault_acc_balances_per_share = revenue_registry.vault_acc_balances_per_share.get(revenue_coin_type);
            let pending = claimable_revenue_(revenue_registry, revenue_coin_type, tokenized_asset);
            let asset_revenue_debts_obj = dynamic_object_field::borrow_mut<ID, AssetRevenueDebt>(&mut revenue_registry.id, object::id(tokenized_asset));
            if (!asset_revenue_debts_obj.asset_revenue_debts.contains(revenue_coin_type)) {
                asset_revenue_debts_obj.asset_revenue_debts.insert(*revenue_coin_type, int::zero());
            };
            *asset_revenue_debts_obj.asset_revenue_debts.get_mut(revenue_coin_type) = int::from_u256(*vault_acc_balances_per_share * ((balance - amount) as u256) / PRECISION - (pending as u256));

            i = i + 1;
        }
    } 

    public(package) fun destroy<T>(
        revenue_registry: &mut RevenueRegistry<T>,
        tokenized_asset: &TokenizedAsset<T>
    ) {
        let revenue_coins = revenue_registry.revenue_coins.keys();
        let revenue_coins_len = revenue_coins.length();
        let mut i = 0;
        while(i < revenue_coins_len) {
            let revenue_coin_type = revenue_coins.borrow(i);
            let pending = claimable_revenue_(revenue_registry, revenue_coin_type, tokenized_asset);
            assert!(pending == 0, EDestroyAssetWithPendingRevenue);
            i = i + 1;
        };

        let AssetRevenueDebt {id, asset_id: _, asset_revenue_debts: _} =  dynamic_object_field::remove<ID, AssetRevenueDebt>(&mut revenue_registry.id, object::id(tokenized_asset));
        id.delete();
    }

    public(package) fun claim_revenue<T, R>(
        revenue_registry: &mut RevenueRegistry<T>,
        tokenized_asset: &TokenizedAsset<T>, // ID of the TokenizedAsset
        ctx: &mut TxContext
    ): Coin<R> {
        let revenue_coin_type = type_name::get<R>();
        let pending = claimable_revenue_(revenue_registry, &revenue_coin_type, tokenized_asset);
        assert!(pending > 0, ENothingToClaim);
        
        let balance = tokenized_asset.value();
        let vault_acc_balances_per_share = revenue_registry.vault_acc_balances_per_share.get(&revenue_coin_type);
        let asset_revenue_debts_obj = dynamic_object_field::borrow_mut<ID, AssetRevenueDebt>(&mut revenue_registry.id, object::id(tokenized_asset));
        if(!asset_revenue_debts_obj.asset_revenue_debts.contains(&revenue_coin_type)) {
            asset_revenue_debts_obj.asset_revenue_debts.insert(revenue_coin_type, int::from_u256(*vault_acc_balances_per_share * (balance as u256) / PRECISION));
        } else {
            *asset_revenue_debts_obj.asset_revenue_debts.get_mut(&revenue_coin_type) = int::from_u256(*vault_acc_balances_per_share * (balance as u256) / PRECISION);
        };
        
        let coin_vault = dynamic_object_field::borrow_mut<TypeName, CoinVault<R>>(&mut revenue_registry.id, revenue_coin_type);



        event::emit(RevenueClaimedEvent{
            asset_id: object::id(tokenized_asset),
            asset_type: type_name::get<T>().into_string(),
            revenue_coin_type: revenue_coin_type.into_string(),
            revenue: pending
        });

        coin::from_balance(coin_vault.remaining_revenue.split(pending), ctx)
    }

    public fun claimable_revenue<T, R>(
        revenue_registry: &RevenueRegistry<T>,
        tokenized_asset: &TokenizedAsset<T>, // ID of the TokenizedAsset
    ): u64 {
        claimable_revenue_(revenue_registry, &type_name::get<R>(), tokenized_asset)
    }
    
    public fun claimable_revenue_<T>(
        revenue_registry: &RevenueRegistry<T>,
        revenue_coin_type: &TypeName, // Type of revenue coin
        tokenized_asset: &TokenizedAsset<T>, // ID of the TokenizedAsset
    ): u64 {
        // accBalance - accumulated revenue tokens in the vault
        // totalSupply = totalSupply() - totalSupply of RoyaltyTokens of the vault (IpRoyaltyVault)
        // accBalancePerShare = accBalance / totalSupply
        // userAmount = balanceOf(user) - user amount of RoyaltyTokens (IpRoyaltyVault)
        // means how much share the user has
        // pending = (accBalancePerShare * userAmount) - rewardDebt
        assert!(revenue_registry.revenue_coins.contains(revenue_coin_type), EInvalidRevenueCoinType);
        let vault_acc_balances_per_share = revenue_registry.vault_acc_balances_per_share.get(revenue_coin_type);
        let asset_revenue_debts_obj = dynamic_object_field::borrow<ID, AssetRevenueDebt>(&revenue_registry.id, object::id(tokenized_asset));
        let mut asset_revenue_debt_opt = asset_revenue_debts_obj.asset_revenue_debts.try_get(revenue_coin_type);
        let asset_revenue_debt = if (asset_revenue_debt_opt.is_none()) {
            int::zero()
        } else {
            asset_revenue_debt_opt.extract()
        };

        if (asset_revenue_debt.is_positive()) {
            ((*vault_acc_balances_per_share as u256) * (tokenized_asset.value() as u256) / PRECISION - asset_revenue_debt.to_u256()) as u64
        } else {
            ((*vault_acc_balances_per_share as u256) * (tokenized_asset.value() as u256) / PRECISION - asset_revenue_debt.abs().to_u256()) as u64
        }
    }
}