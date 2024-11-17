/// The `tokenized_asset` module will operate in a manner similar to the `coin` library. 
/// When it receives a new one-time witness type, it will create a unique representation of
/// a fractional asset.
/// This module employs similar implementations to some methods found in the Coin module.
/// It encompasses functionalities pertinent to asset tokenization,
/// including new asset creation, minting, splitting, joining, and burning.
module tokenization::tokenized_asset {
    // std lib imports
    use std::string::{String};
    use std::ascii;
    use std::type_name::{Self};

    // Sui imports
    use sui::url::{Self, Url};
    use sui::balance::{Self, Supply, Balance};
    use sui::event::emit;
    
    const ENoSupply: u64 = 1;
    const EInsufficientTotalSupply: u64 = 2;
    const EZeroAmount: u64 = 3;
    const ENonBurnable: u64 = 4;
    const EInsufficientBalance: u64 = 5;
    const EZeroBalance: u64 = 6;

    /// An AssetCap should be generated for each new Asset we wish to represent
    /// as a fractional NFT
    public struct AssetCap<phantom T> has key, store {
        id: UID,
        /// The current circulating supply
        supply: Supply<T>,
        /// The total max supply allowed to exist at any time that was issued
        /// upon creation of Asset T
        total_supply: u64,
        /// TAs of type T can be burned by the admin
	    burnable: bool
    }

    /// The AssetMetadata struct defines the metadata representing the entire asset.
    /// that we intend to fractionalize. 
    public struct AssetMetadata<phantom T> has key, store {
        id: UID,
        /// Name of the asset
        name: String,
        /// The total max supply allowed to exist at any time that was issued
        /// upon creation of Asset T
        total_supply: u64,
        /// Symbol for the asset
        symbol: ascii::String,
        /// Description of the asset
        description: String,
        /// URL for the asset logo
        icon_url: Option<Url>
    }

    /// TokenizedAsset(TA) struct represents a tokenized asset of type T.
    public struct TokenizedAsset<phantom T> has key, store {
        id: UID,
        /// The balance of the tokenized asset.
        balance: Balance<T>,
    }

    /// Event emitted when a new asset is created.
    public struct AssetCreated has copy, drop {
        asset_metadata: ID,
        name: ascii::String
    }

    /// Creates a new Asset representation that can be fractionalized.
    public(package) fun new_asset<T: drop>(
        witness: T,
        total_supply: u64,
        symbol: ascii::String,
        name: String,
        description: String,
        mut icon_url: Option<vector<u8>>,
        burnable: bool,
        ctx: &mut TxContext
    ): (AssetCap<T>, AssetMetadata<T>) {
        assert!(total_supply > 0, EInsufficientTotalSupply);

        let asset_cap = AssetCap {
            id: object::new(ctx),
            supply: balance::create_supply(witness),
            total_supply,
            burnable
        };

        let icon_url = if(icon_url.is_some()) {
            option::some<Url>(url::new_unsafe_from_bytes(icon_url.extract()))
        } else {
            option::none()
        };
        let asset_metadata = AssetMetadata {
            id: object::new(ctx),
            name,
            total_supply,
            symbol,
            description,
            icon_url
        };

        emit(AssetCreated {
            asset_metadata: object::id(&asset_metadata),
            name: type_name::get<T>().into_string() 
        });

        (asset_cap, asset_metadata)
    }

    /// Mints a TA with the specified fields.
    /// it is considered a fungible token (FT).
    public(package) fun mint<T>(
        cap: &mut AssetCap<T>,
        value: u64,
        ctx: &mut TxContext
    ): TokenizedAsset<T> {
        let supply_value = supply(cap);
        assert!(supply_value + value <= cap.total_supply, ENoSupply);
        assert!(value > 0, EZeroAmount);
        let balance = cap.supply.increase_supply(value);

        TokenizedAsset {
            id: object::new(ctx),
            balance,
        }
    }

    /// Split a tokenized_asset.
    /// Creates a new tokenized asset of balance split_amount and updates tokenized_asset's balance accordingly.
    public(package) fun split<T>(
        self: &mut TokenizedAsset<T>,
        split_amount: u64,
        ctx: &mut TxContext
    ): TokenizedAsset<T> {
        let balance_value = value(self);
        assert!(balance_value > 1 && split_amount < balance_value, EInsufficientBalance);
        assert!(split_amount > 0, EZeroBalance);

        let new_balance = self.balance.split(split_amount);

        TokenizedAsset {
            id: object::new(ctx),
            balance: new_balance,
        }
    }


    /// Merge other's balance into self's balance.
    /// other is burned.
    public(package) fun join<T>(
        self: &mut TokenizedAsset<T>,
        other: TokenizedAsset<T>
    ): ID {
        let item = object::id(&other);
        let TokenizedAsset { id, balance,} = other;
        self.balance.join(balance);
        id.delete();

        item
    }

    /// Destroy the tokenized asset and decrease the supply in `cap` accordingly.
    public(package) fun burn<T>(
        cap: &mut AssetCap<T>,
        tokenized_asset: TokenizedAsset<T>
    ) {
        assert!(cap.burnable == true, ENonBurnable);
        let TokenizedAsset { id, balance} = tokenized_asset;
        cap.supply.decrease_supply(balance);
        id.delete();
    }

    /// Returns the value of the total supply.
    public fun total_supply<T>(cap: &AssetCap<T>): u64 {
        cap.total_supply
    }

    /// Returns the value of the current circulating supply.
    public fun supply<T>(cap: &AssetCap<T>): u64 {
        cap.supply.supply_value()
    }

    /// Returns the balance value of a TokenizedAsset<T>.
    public fun value<T>(tokenized_asset: &TokenizedAsset<T>): u64 {
        tokenized_asset.balance.value()
    }
}