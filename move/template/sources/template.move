module template::template {
    // std lib imports
    use std::string::{Self};
    use std::ascii;

    // Asset tokenization imports
    use tokenization::tokenization::{Self};

    public struct TEMPLATE has drop {}

    const TOTAL_SUPPLY: u64 = 100;
    const SYMBOL: vector<u8> = b"Symbol";
    const NAME: vector<u8> = b"Name";
    const DESCRIPTION: vector<u8> = b"Description";
    const ICON_URL: vector<u8> = b"icon_url";
    const BURNABLE: bool = true;

    fun init (otw: TEMPLATE, ctx: &mut TxContext){

        let icon_url = if (ICON_URL == b"") {
            option::none()
        } else {
            option::some(ICON_URL)
        };

        let (asset_cap, asset_metadata, revenue_registry, operator_cap) = tokenization::new_asset_<TEMPLATE>(
            otw, 
            TOTAL_SUPPLY, 
            ascii::string(SYMBOL), 
            string::utf8(NAME), 
            string::utf8(DESCRIPTION), 
            icon_url, 
            BURNABLE,
            ctx
        );
        
        transfer::public_share_object(asset_metadata);
        transfer::public_share_object(asset_cap);
        transfer::public_share_object(revenue_registry);
        transfer::public_transfer(operator_cap, ctx.sender());
    }

    #[test_only]
    public fun init_for_testing(ctx: &mut TxContext) {
        init(TEMPLATE{}, ctx);
    }

}