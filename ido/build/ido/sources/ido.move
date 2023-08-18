module resource_admin::ido {
    use std::signer;
    use std::vector;
    use aptos_framework::event::{Self, EventHandle};
    use aptos_std::table::{Self, Table};
    use aptos_std::math64;
    use aptos_framework::account::{Self,SignerCapability};
    use aptos_framework::resource_account;
    use aptos_framework::coin;
    use aptos_framework::timestamp;
    use 0x1459a60535295c06c03dbfa461efee1b9127da5e83a8b0ca4a7d40e0c44031a7::idoCoin::IdoCoin;
    use 0xbbc55d03f70ac66274200299d410a1441043af093fd601ecfd0e9d44692a9cb7::stableCoin::StableCoin;


    const MAX_U64:u64=0xFFFFFFFFFFFFFFFF;

    
    struct Purchases has key{
        tokenAllocationBought:u64,
        position:u64,
        tokensBought:Table<u64,u64>,
        
    }


    struct ActualSigner has key{
        signCap:SignerCapability,
        issuer:address
    }

    struct AllocationBoughtEvent has store,drop {
        user:address,
        amount:u64
    }

    struct ClaimedEvent has store,drop {
        user:address,
        amount:u64
    }

    struct IdoMetadata has key {
        allocation_bought:EventHandle<AllocationBoughtEvent>,
        claimed_token:EventHandle<ClaimedEvent>,
    }
        
        
    struct IdoData has key{
        trancheLength:vector<u64>,
        trancheWeightage:vector<u64>,
        maxAllocPerUserPerTier:vector<u64>,
        active:bool,
        tge:u64,
        totalTokenAllocation:u64,
        minAllocationPermitted:u64,
        maxAllocationPermitted:u64,
        tokensPurchased:u64,
        tokenPerUsd:u64,
        startTime:u64,
        guranteedSaleDuration:u64,
        blacklist:Table<address,bool>

    }

    fun init_module(resource_signer:&signer) {
        let res_signer_cap=resource_account::retrieve_resource_account_cap(resource_signer,@admin);
        
        move_to(resource_signer,ActualSigner{
            signCap:res_signer_cap,
            issuer:@admin
        });

    }

    fun register_account(user:&signer) {
        assert!(!is_account_registered(signer::address_of(user)),1);
        move_to(user,Purchases{
                tokenAllocationBought:0,
                position:0,
                tokensBought:table::new<u64,u64>()
        });
        move_to(user,IdoMetadata{
            allocation_bought:account::new_event_handle<AllocationBoughtEvent>(user),
            claimed_token:account::new_event_handle<ClaimedEvent>(user),

        })

    }

    #[view]
    public fun is_account_registered(user:address):bool {
        exists<Purchases>(user)&&exists<IdoMetadata>(user)
    }

    public entry fun issue(user:&signer,_totalTokenAllocation:u64,_maxTokenAllocPerUserPerTier:vector<u64>,_maxTokenAllocationPermitted:u64,_tokenPerUsd:u64,
        _trancheWeightage:vector<u64>,_trancheLength:vector<u64>,_guranteedSaleDuration:u64) acquires ActualSigner {
        let user_address=signer::address_of(user);
        let actualSigner= borrow_global_mut<ActualSigner>(@resource_admin);
        assert!(user_address==actualSigner.issuer,2);
        let resource_signer=account::create_signer_with_capability(&actualSigner.signCap);                

        

        move_to(
            & resource_signer,IdoData {
            trancheLength:_trancheLength,
            trancheWeightage:_trancheWeightage,
            maxAllocPerUserPerTier:_maxTokenAllocPerUserPerTier,
            active:false,
            tge:MAX_U64,
            totalTokenAllocation:_totalTokenAllocation,
            minAllocationPermitted:*vector::borrow(&_maxTokenAllocPerUserPerTier,(vector::length(&_maxTokenAllocPerUserPerTier)-1)/2),
            maxAllocationPermitted:_maxTokenAllocationPermitted,
            tokensPurchased:0,
            tokenPerUsd:_tokenPerUsd,
            startTime:MAX_U64,
            guranteedSaleDuration:_guranteedSaleDuration,
            blacklist:table::new<address,bool>()

            });

        if(!coin::is_account_registered<IdoCoin>(@resource_admin)){
                coin::register<IdoCoin>(& resource_signer);

        };
            
        if(!coin::is_account_registered<StableCoin>(@resource_admin)){
                coin::register<StableCoin>(& resource_signer);
        }
            
            

    }

    public fun check_issuer(user:address):bool acquires ActualSigner{
        let actualSigner=borrow_global<ActualSigner>(@resource_admin);
        actualSigner.issuer==user
    }
        
    public entry fun update_tge(issuer:&signer,timestamp:u64) acquires ActualSigner,IdoData{
        assert!(check_issuer(signer::address_of(issuer)),3);
        let idoData=&mut borrow_global_mut<IdoData>(@resource_admin).tge;
        assert!(timestamp::now_seconds()<*idoData,4);
        assert!(timestamp::now_seconds()<timestamp,5);
        *idoData=timestamp;

    }

    public entry fun deposit_tokens(issuer:&signer) acquires ActualSigner,IdoData {
        assert!(check_issuer(signer::address_of(issuer)),3);
        let idoData=borrow_global_mut<IdoData>(@resource_admin);
        assert!(!idoData.active,5);
        coin::transfer<IdoCoin>(issuer,@resource_admin,idoData.totalTokenAllocation);
        idoData.active=true;

    }

    public entry fun submit_tokens(issuer:&signer,amount:u64) acquires ActualSigner,IdoData {
        assert!(check_issuer(signer::address_of(issuer)),3);
        let idoData=borrow_global_mut<IdoData>(@resource_admin);
        coin::transfer<IdoCoin>(issuer,@resource_admin,amount);
        idoData.active=true;

    }

    public entry fun update_start_time(issuer:&signer,timestamp:u64) acquires ActualSigner,IdoData {
        assert!(check_issuer(signer::address_of(issuer)),3);
        let idoData=&mut borrow_global_mut<IdoData>(@resource_admin).startTime;
        assert!(timestamp::now_seconds()<*idoData,4);
        assert!(timestamp::now_seconds()<timestamp,5);
        *idoData=timestamp;

    }

    public entry fun flip_ido_status(issuer:&signer) acquires ActualSigner,IdoData {
        assert!(check_issuer(signer::address_of(issuer)),3);
        let actualSigner= borrow_global<ActualSigner>(@resource_admin);   
        let idoData=&mut borrow_global_mut<IdoData>(@resource_admin).active;
        let resource_signer=account::create_signer_with_capability(&actualSigner.signCap);     
        if(*idoData){
            coin::transfer<StableCoin>(&resource_signer,actualSigner.issuer,coin::balance<StableCoin>(actualSigner.issuer));
        };
        *idoData=!*idoData;

    }

    public entry fun buy_an_allocation(_user:&signer,_pay:u64,_staked:u64) acquires Purchases,IdoData,IdoMetadata {
        assert!(_pay>0,6);
        let user_address=signer::address_of(_user);
        let idoData=borrow_global_mut<IdoData>(@resource_admin);
        assert!(idoData.active,7);
        assert!(timestamp::now_seconds()>=idoData.startTime,8);
        let stable_decimal=coin::decimals<StableCoin>();
        let pur=(_pay*idoData.tokenPerUsd)/math64::pow(10,(stable_decimal as u64));
        assert!(idoData.tokensPurchased+pur<=idoData.totalTokenAllocation,9);

        let id:u64;
            if (_staked >= 30000){
            id =0;
        } else if (_staked >= 15000  && _staked < 30000 ){
            id =1;
        } else if(_staked >= 7500  && _staked < 15000 ){
            id =2;
        } else if(_staked >= 2000 && _staked < 7500 ){
            id =3;
        } else{
            abort 10
        };

        let purchases= borrow_global_mut<Purchases>(user_address);

        assert!(purchases.tokenAllocationBought+pur>=idoData.minAllocationPermitted,11);

        if(timestamp::now_seconds()<idoData.startTime+idoData.guranteedSaleDuration){
            assert!(purchases.tokenAllocationBought+pur<=*vector::borrow(&idoData.maxAllocPerUserPerTier,id),12);
            let tokens_bought=table::borrow_mut_with_default(&mut purchases.tokensBought,1,pur);
            if(*tokens_bought!=pur){
                *tokens_bought=*tokens_bought+pur;
            }
        }
        else {
            assert!(purchases.tokenAllocationBought+pur<=idoData.maxAllocationPermitted,13);
            let tokens_bought=table::borrow_mut_with_default(&mut purchases.tokensBought,2,pur);
            if(*tokens_bought!=pur){
                *tokens_bought=*tokens_bought+pur;
            }
        };

        purchases.tokenAllocationBought=purchases.tokenAllocationBought+pur;
        idoData.tokensPurchased=idoData.tokensPurchased+pur;

        coin::transfer<StableCoin>(_user,@resource_admin,_pay);

        let allocation=borrow_global_mut<IdoMetadata>(user_address);

        event::emit_event<AllocationBoughtEvent>(
        &mut allocation.allocation_bought,
        AllocationBoughtEvent {user:user_address,amount:pur });

    }

    #[view]
    public fun get_token_sold():u64 acquires IdoData {
        borrow_global<IdoData>(@resource_admin).tokensPurchased
    }

    #[view]
    public fun get_amount_raised():u64 acquires IdoData {
        let ido_data=borrow_global<IdoData>(@resource_admin);
        (ido_data.tokensPurchased*math64::pow(10,(coin::decimals<StableCoin>() as u64)))/ido_data.tokenPerUsd
    }

    public entry fun withdraw_tokens(issuer:&signer) acquires ActualSigner{ 
        assert!(check_issuer(signer::address_of(issuer)),3);
        let actualSigner= borrow_global<ActualSigner>(@resource_admin);
        let resource_signer=account::create_signer_with_capability(&actualSigner.signCap); 
        coin::transfer<StableCoin>(&resource_signer,actualSigner.issuer,coin::balance<StableCoin>(actualSigner.issuer));
        
    }

    public entry fun set_blacklist(issuer:&signer,users:vector<address>,blacklist:bool) acquires ActualSigner,IdoData {
        let len:u64=vector::length(& users);
        assert!(len < 200 , 16);
        assert!(check_issuer(signer::address_of(issuer)),3);
        let ido_data=&mut borrow_global_mut<IdoData>(@resource_admin).blacklist;
        let counter:u64=0;
        loop{
        table::borrow_mut_with_default(ido_data,*vector::borrow(& users,counter),blacklist);
        counter=counter+1;
        if(counter==len)
        break;
        }

        
    }
    

    public entry fun reedem(user:&signer) acquires IdoData,ActualSigner,IdoMetadata,Purchases {
        let ido_data=borrow_global_mut<IdoData>(@resource_admin);
        let actual_signer=borrow_global_mut<ActualSigner>(@resource_admin);
        let user_address=signer::address_of(user);
        let claim=borrow_global_mut<IdoMetadata>(user_address);
        let purchases=borrow_global_mut<Purchases>(user_address);
        assert!(!*table::borrow(& ido_data.blacklist,user_address),17);
        assert!(timestamp::now_seconds()>ido_data.tge,18);
        let redeemablePercentage:u64=0;
        let tranch_length=vector::length(&ido_data.trancheLength);

        assert!(purchases.position<tranch_length,19);
        let counter:u64=purchases.position;

        while(counter < tranch_length) {

            if(ido_data.tge+*vector::borrow(& ido_data.trancheLength,counter)<timestamp::now_seconds()){
                redeemablePercentage=redeemablePercentage+*vector::borrow(&ido_data.trancheWeightage,counter);
                if(counter==tranch_length-1){
                    purchases.position=tranch_length;
                    break
                }
            }
            else {
                purchases.position=counter;
                break
            };   

            counter=counter+1;

        };

        assert!(redeemablePercentage > 0 ,20);
        let coins:u64=(purchases.tokenAllocationBought*redeemablePercentage)/math64::pow(10,(coin::decimals<IdoCoin>() as u64)+2);
        let resource_signer=account::create_signer_with_capability(&actual_signer.signCap);  
        
        coin::transfer<IdoCoin>(&resource_signer,user_address,coins);

        event::emit_event<ClaimedEvent>(
        &mut claim.claimed_token,
        ClaimedEvent {user:user_address,amount:coins});



       



    }

}
  
    //     redeemablePercentage=redeemablePercentage;
    //     require(redeemablePercentage > 0, "GenIDO: zero amount cannot be claimed");
    //     uint256 tokens = (selectedPurchase.tokenAllocationBought*redeemablePercentage)/(10**20);
    //     require(IERC20(underlyingToken).transfer(msg.sender, tokens));

    //     emit claimed(msg.sender, tokens);
    // }

    // function getBlockTimestamp() internal view returns (uint) {
    //     // solium-disable-next-line security/no-block-members
    //     return block.timestamp;
    // }