module coin_address::idoCoin {
    use std::signer;
    use std::string;
    use std::vector;
    use aptos_framework::coin;
    use aptos_framework::event;
    use aptos_framework::account;
    use aptos_framework::resource_account;


    struct IdoCoin has key{}


    struct CoinMintingEvent has store,drop {
        minter:address,
        amount:u64,
    }

    struct CoinBurningEvent has store,drop {
        burner:address,
        amount:u64,
    }

    struct CoinFreezingEvent has store,drop {
        freezer:address,
        user:address,
    }

    struct CoinReleasingEvent has store,drop {
        releaser:address,
        user:address,
    }

    struct CoinAccessData has key{
        signer_cap:account::SignerCapability,
        admin:address,
        delegators:vector<address>,
    }

    struct Capabilities has key {
        mint_cap:coin::MintCapability<IdoCoin>,
        burn_cap:coin::BurnCapability<IdoCoin>,
        freeze_cap:coin::FreezeCapability<IdoCoin>
    } 

    struct CoinMetadata has key{
        coin_minting_event:event::EventHandle<CoinMintingEvent>,
        coin_burning_event:event::EventHandle<CoinBurningEvent>,
        coin_freezing_event:event::EventHandle<CoinFreezingEvent>,
        coin_releasing_event:event::EventHandle<CoinReleasingEvent>
    }


    fun init_module(resource_signer:&signer) {
        let signer_cap=resource_account::retrieve_resource_account_cap(resource_signer,@admin);

        move_to(resource_signer,CoinAccessData{
            signer_cap,
            admin:@admin,
            delegators:vector::empty<address>()
        });
    }

    #[view]
    public fun is_account_registered(user:address):bool{
        exists<CoinMetadata>(user)
    }

    public entry fun register_Account(user:&signer) {
        let user_address=signer::address_of(user);
        if(!coin::is_account_registered<IdoCoin>(user_address)){
            coin::register<IdoCoin>(user);
        };

        if(!is_account_registered(user_address)){
            move_to(user,CoinMetadata{
            coin_minting_event:account::new_event_handle<CoinMintingEvent>(user),
            coin_burning_event:account::new_event_handle<CoinBurningEvent>(user),
            coin_freezing_event:account::new_event_handle<CoinFreezingEvent>(user),
            coin_releasing_event:account::new_event_handle<CoinReleasingEvent>(user),
        });
        }
    }

    public entry fun issue(user:&signer) acquires CoinAccessData{
        assert!(!exists<Capabilities>(@coin_address),1);
        let user_address=signer::address_of(user);
        let access=borrow_global<CoinAccessData>(@coin_address);
        assert!(access.admin==user_address,2);

        let coin_sign=&account::create_signer_with_capability(&access.signer_cap);

        let(burn_cap,freeze_cap,mint_cap)=coin::initialize<IdoCoin>(
            coin_sign,
            string::utf8(b"IdoCoin"),
            string::utf8(b"SBC"),
            8,
            true
        );

        move_to(coin_sign,Capabilities{
            mint_cap,
            burn_cap,
            freeze_cap
        });
    }

    public entry fun set_admin(admin: &signer, admin_addr: address) acquires CoinAccessData{
        let addr = signer::address_of(admin);
        let access=borrow_global_mut<CoinAccessData>(@coin_address);
        assert!(access.admin==addr,3);
        access.admin = admin_addr;
    }


    public entry fun add_delegators(user:&signer,delegator:address) acquires CoinAccessData{
        let access=borrow_global_mut<CoinAccessData>(@coin_address);
        let user_address=signer::address_of(user);
        assert!(access.admin==user_address,3);
        vector::for_each_ref(&mut access.delegators, |element| {
        let element:address= *element;
        assert!(element != delegator, 4);
        });
        vector::push_back(&mut access.delegators, delegator);

    }

    #[view]
    public fun isAuthorized(user_address:address):bool acquires CoinAccessData {
        let access = borrow_global<CoinAccessData>(@coin_address);
        if (user_address == access.admin) {
            return true
        };
        let result= vector::contains(&access.delegators,&user_address);
        return result
    }

    public entry fun mint(user:&signer,to:address,_value:u64) acquires CoinAccessData,CoinMetadata,Capabilities{
        assert!(exists<Capabilities>(@coin_address),5);
        let user_address=signer::address_of(user);
        assert!(isAuthorized(user_address),6);
        assert!(is_account_registered(to),7);
        let mint_cap = &borrow_global<Capabilities>(@coin_address).mint_cap;
        let coins = coin::mint<IdoCoin>(_value, mint_cap);
        coin::deposit<IdoCoin>(to, coins);

        let coin_store = borrow_global_mut<CoinMetadata>(to);
        event::emit_event<CoinMintingEvent>(
            &mut coin_store.coin_minting_event,
            CoinMintingEvent {minter:user_address,amount:_value });


    }

    public entry fun burn(user:&signer,to:address,_value:u64) acquires CoinAccessData,CoinMetadata,Capabilities{
        assert!(exists<Capabilities>(@coin_address),5);
        let user_address=signer::address_of(user);
        assert!(isAuthorized(user_address)||user_address==to,6);
        assert!(is_account_registered(to),7);
        let burn_cap = &borrow_global<Capabilities>(@coin_address).burn_cap;
        coin::burn_from<IdoCoin>(to,_value, burn_cap);
        let coin_store = borrow_global_mut<CoinMetadata>(to);
        event::emit_event<CoinBurningEvent>(
            &mut coin_store.coin_burning_event,
            CoinBurningEvent { burner:user_address,amount:_value });


    }

    public entry fun freezing(user:&signer,to:address,_value:u64) acquires CoinAccessData,CoinMetadata,Capabilities{
        assert!(exists<Capabilities>(@coin_address),5);
        let user_address=signer::address_of(user);
        assert!(isAuthorized(user_address),6);
        assert!(is_account_registered(to),7);
        let freeze_cap = &borrow_global<Capabilities>(@coin_address).freeze_cap;
        coin::freeze_coin_store<IdoCoin>(to, freeze_cap);
        let coin_store = borrow_global_mut<CoinMetadata>(to);
        event::emit_event<CoinFreezingEvent>(
            &mut coin_store.coin_freezing_event,
            CoinFreezingEvent {freezer:user_address,user:to});


    }

    public entry fun unFreezing(user:&signer,to:address,_value:u64) acquires CoinAccessData,CoinMetadata,Capabilities{
        assert!(exists<Capabilities>(@coin_address),5);
        let user_address=signer::address_of(user);
        assert!(isAuthorized(user_address),6);
        assert!(is_account_registered(to),7);
        let mint_cap = &borrow_global<Capabilities>(@coin_address).freeze_cap;
        coin::unfreeze_coin_store<IdoCoin>(to, mint_cap);
        let coin_store = borrow_global_mut<CoinMetadata>(to);
        event::emit_event<CoinReleasingEvent>(
            &mut coin_store.coin_releasing_event,
            CoinReleasingEvent { releaser:user_address,user:to });


    }





}