
#[test_only]
#[allow(unused_use)]
module tokenization::tokenization_test {
    use tokenization::tokenization::{Self, MinterCap};
    use tokenization::tokenized_asset::{Self, AssetCap};
    use tokenization::revenue_registry::{Self, RevenueRegistry, OperatorCap};

    use sui::test_utils::create_one_time_witness;
    use sui::test_scenario::{Self as test, next_tx, ctx, Scenario};
    use sui::coin::{Self, mint_for_testing as mint, burn_for_testing as burn};
    use sui::sui::SUI;

    use std::string;
    use std::ascii;
    use std::type_name::{Self};

    public struct TOKENIZATION_TEST has drop {}
    public struct TOKEN has drop {}
    public struct TOKEN2 has drop {}

    const ADMIN: address = @0xAAAA;
    const USER: address = @0xBBBB;
    const PRECISION: u256 = 1_000_000_000;

    #[test]
    fun test_init_package() {
        let mut scenario = test::begin(ADMIN);

        scenario.next_tx(ADMIN);
        {
            tokenization::init_for_testing(scenario.ctx());
        };

        scenario.next_tx(ADMIN);
        {
            let minter_cap = scenario.take_from_sender<MinterCap>();

            scenario.return_to_sender(minter_cap);
        };

        scenario.end();
    }

    #[test]
    fun test_create_asset(){
        let mut scenario = test::begin(ADMIN);
        init_data(&mut scenario);

        scenario.next_tx(ADMIN);
        {
            let minter_cap = scenario.take_from_sender<MinterCap>();

            let (asset_cap, asset_metadata, revenue_registry, operator_cap) = tokenization::new_asset_(
                create_one_time_witness<TOKENIZATION_TEST>(), 
                1000000,
                ascii::string(b"Test Token"), 
                string::utf8(b"TT"), 
                string::utf8(b"Description"), 
                option::none(), 
                true,
                scenario.ctx()
            );
            scenario.return_to_sender(minter_cap);
            assert!(asset_cap.total_supply() == 1000000);
            assert!(asset_cap.supply() == 0);
            
            let (revenue_coins, vault_acc_balances_per_shares) = revenue_registry.get_revenue_registry();
            assert!(revenue_coins.size() == 0);
            assert!(vault_acc_balances_per_shares.size() == 0);

            transfer::public_share_object(asset_cap);
            transfer::public_share_object(asset_metadata);
            transfer::public_share_object(revenue_registry);
            transfer::public_transfer(operator_cap, scenario.ctx().sender());
        };

        scenario.next_tx(ADMIN);
        {
            let (mut asset_cap, minter_cap, mut revenue_registry, operator_cap) = get_cap<TOKENIZATION_TEST>(&scenario);
            let mut asset = tokenization::mint(&mut asset_cap, &minter_cap, &mut revenue_registry, 1000, scenario.ctx());
            assert!(asset.value() == 1000);
            assert!(asset_cap.supply() == 1000);
            let asset_revenue_debts = revenue_registry.get_asset_revenue_debts(&asset);
            assert!(asset_revenue_debts.size() == 0);

            let mut new_asset = tokenization::split(&mut revenue_registry, &mut asset, 10, scenario.ctx());
            assert!(asset.value() == 990);
            assert!(new_asset.value() == 10);

            tokenization::join(&mut revenue_registry, &mut new_asset, asset);
            assert!(new_asset.value() == 1000);
            tokenization::burn(&mut asset_cap, &minter_cap, &mut revenue_registry, new_asset);

            assert!(asset_cap.supply() == 0);

            return_cap(&scenario, asset_cap, minter_cap, revenue_registry, operator_cap)
        };

        scenario.end();
    }

    #[test]
    fun test_revenue(){
        let mut scenario = test::begin(ADMIN);
        init_data(&mut scenario);

        scenario.next_tx(ADMIN);
        {
            let minter_cap = scenario.take_from_sender<MinterCap>();

            let (mut asset_cap, asset_metadata, mut revenue_registry, operator_cap) = tokenization::new_asset_(
                create_one_time_witness<TOKENIZATION_TEST>(), 
                1000000,
                ascii::string(b"Test Token"), 
                string::utf8(b"TT"), 
                string::utf8(b"Description"), 
                option::none(), 
                true,
                scenario.ctx()
            );

            let mut asset1 = tokenization::mint(&mut asset_cap, &minter_cap, &mut revenue_registry, 7500, scenario.ctx());
            let asset2 = tokenization::mint(&mut asset_cap, &minter_cap, &mut revenue_registry, 2500, scenario.ctx());

            let revenue_coin = mint<TOKEN>(100000, scenario.ctx());

            tokenization::deposit_revenue<TOKENIZATION_TEST, TOKEN>(
                &mut revenue_registry,
                &operator_cap,
                &asset_cap,
                revenue_coin, 
                scenario.ctx()
            );
            let (revenue_coins, vault_acc_balances_per_share) = (revenue_registry.get_revenue_registry());
            assert!(revenue_coins.size() == 1);
            assert!(vault_acc_balances_per_share.size() == 1);
            assert!(revenue_coins.contains(&type_name::get<TOKEN>()));
            assert!(*vault_acc_balances_per_share.get(&type_name::get<TOKEN>()) == (100000 as u256) * PRECISION / 10000);

            assert!(revenue_registry.claimable_revenue<TOKENIZATION_TEST, TOKEN>(&asset1) == 75000);
            assert!(revenue_registry.claimable_revenue<TOKENIZATION_TEST, TOKEN>(&asset2) == 25000);

            let revenue = tokenization::claim_revenue<TOKENIZATION_TEST, TOKEN>(&mut revenue_registry, &asset1, scenario.ctx());
            assert!(revenue.burn() == 75000);
            assert!(revenue_registry.remaining_revenue<TOKENIZATION_TEST, TOKEN>() == 25000);
            let asset_revenue_debts = revenue_registry.get_asset_revenue_debts(&asset1);
            assert!(asset_revenue_debts.size() == 1);
            assert!((*asset_revenue_debts.get(&type_name::get<TOKEN>())).to_u64() ==  75000);

            let asset3 = tokenization::mint(&mut asset_cap, &minter_cap, &mut revenue_registry, 10000, scenario.ctx());
            assert!(revenue_registry.claimable_revenue<TOKENIZATION_TEST, TOKEN>(&asset3) == 0);

            let revenue_coin = mint<TOKEN2>(100000, scenario.ctx());
            tokenization::deposit_revenue<TOKENIZATION_TEST, TOKEN2>(
                &mut revenue_registry,
                &operator_cap,
                &asset_cap,
                revenue_coin, 
                scenario.ctx()
            );

            let (revenue_coins, vault_acc_balances_per_share) = (revenue_registry.get_revenue_registry());
            assert!(revenue_coins.size() == 2);
            assert!(vault_acc_balances_per_share.size() == 2);
            assert!(revenue_coins.contains(&type_name::get<TOKEN2>()));
            assert!(*vault_acc_balances_per_share.get(&type_name::get<TOKEN2>()) == (100000 as u256) * PRECISION / 20000);

            assert!(revenue_registry.claimable_revenue<TOKENIZATION_TEST, TOKEN2>(&asset1) == 37500);
            assert!(revenue_registry.claimable_revenue<TOKENIZATION_TEST, TOKEN2>(&asset2) == 12500);
            assert!(revenue_registry.claimable_revenue<TOKENIZATION_TEST, TOKEN2>(&asset3) == 50000);

            let revenue = tokenization::claim_revenue<TOKENIZATION_TEST, TOKEN>(&mut revenue_registry, &asset2, scenario.ctx());
            assert!(revenue.burn() == 25000);
            let revenue = tokenization::claim_revenue<TOKENIZATION_TEST, TOKEN2>(&mut revenue_registry, &asset2, scenario.ctx());
            assert!(revenue.burn() == 12500);

            tokenization::join<TOKENIZATION_TEST>(&mut revenue_registry, &mut asset1, asset2);
            let asset_revenue_debts = revenue_registry.get_asset_revenue_debts(&asset1);
            assert!(asset_revenue_debts.size() == 2);
            assert!((*asset_revenue_debts.get(&type_name::get<TOKEN>())).to_u64() ==  100000);
            assert!((*asset_revenue_debts.get(&type_name::get<TOKEN2>())).to_u64() ==  12500);      
            let revenue = tokenization::claim_revenue<TOKENIZATION_TEST, TOKEN2>(&mut revenue_registry, &asset1, scenario.ctx());
            assert!(revenue.burn() == 37500);

            tokenization::burn(&mut asset_cap, &minter_cap, &mut revenue_registry, asset1);
            transfer::public_share_object(asset_cap);
            transfer::public_share_object(asset_metadata);
            transfer::public_transfer(minter_cap, scenario.ctx().sender());
            transfer::public_share_object(revenue_registry);
            transfer::public_transfer(operator_cap, scenario.ctx().sender());
            transfer::public_transfer(asset3, USER);
        };

        scenario.end();
    }

    fun init_data(
        scenario: &mut Scenario,
    ) {
        scenario.next_tx(ADMIN);
        {
            tokenization::init_for_testing(scenario.ctx());
        };
    }

    fun get_cap<T>(
        scenario: &Scenario,
    ):(AssetCap<T>, MinterCap, RevenueRegistry<T>, OperatorCap<T>) {
        let asset_cap = scenario.take_shared<AssetCap<T>>();
        let minter_cap = scenario.take_from_address<MinterCap>(ADMIN);
        let revenue_registry = scenario.take_shared<RevenueRegistry<T>>();
        let operator_cap = scenario.take_from_address<OperatorCap<T>>(ADMIN);
        
        (asset_cap, minter_cap, revenue_registry, operator_cap)
    }
    
    fun return_cap<T>(
        scenario: &Scenario,
        asset_cap: AssetCap<T>,
        minter_cap: MinterCap,
        revenue_registry: RevenueRegistry<T>,
        operator_cap: OperatorCap<T>,
    ) {
        test::return_shared(asset_cap);
        scenario.return_to_sender(minter_cap);
        test::return_shared(revenue_registry);
        scenario.return_to_sender(operator_cap);
    }
}

