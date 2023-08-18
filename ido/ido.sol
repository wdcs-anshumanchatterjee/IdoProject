// We need to use always the current version
pragma solidity 0.8.5;

import "github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/IERC20.sol";
import "github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/proxy/utils/Initializable.sol";


abstract contract IERC20Extented is IERC20 {
    function decimals() public virtual view returns (uint8);
}

contract GenIDO is Initializable {

    event allocationBought(address indexed _user, uint256 _amount, bool _nft);
    event claimed(address indexed _user, uint256 indexed _amount);

    IERC20Extented public underlyingToken;

    IERC20Extented public usdt;

    uint256[] public trancheLength;
    uint256[] public trancheWeightage;
    uint256[] public maxAllocPerUserPerTier;


    address public issuer;
    bool public active = false;
    uint public TGE;

    mapping(address => bool) public blacklist;

    uint256 private totalTokenAllocation;
    uint256 private minAllocationPermitted;
    uint256 private maxAllocationPermitted;
    uint256 private tokensPurchased;
    uint256 public tokenPerUsd;
    uint256 public startTime;
    uint256 private guranteedSaleDuration;
    uint256 private usdDec;
    
    struct Purchases{
        uint112 tokenAllocationBought;//tokens respective to payment
        uint112 position;
    }


    mapping(address => Purchases) public purchases;
    mapping(address=>mapping(uint256=>uint256)) public tokensBought;


    


    modifier onlyIssuer() {
        require(msg.sender == issuer, "GenIDO: Only issuer can update");
        _;

    }
    

    function initialize1(
        address _underlyingToken,
        uint256 _totalTokenAllocation,//enter details as per decimals of _underlyingToken
        uint256[] memory _maxTokenAllocPerUserPerTier,//enter details as per decimals of _underlyingToken
        uint256 _maxTokenAllocationPermitted,//in wei
        uint256 _tokenPerUsd,
        address _usdt,
        uint[] memory _trancheWeightage,//in wei
        uint[] memory _trancheLength,//in seconds
        uint256 _guranteedSaleDuration
    ) 
     external
     initializer          
    {
        underlyingToken = IERC20Extented(_underlyingToken);
        totalTokenAllocation = _totalTokenAllocation;
        usdt = IERC20Extented(_usdt);
        maxAllocPerUserPerTier = _maxTokenAllocPerUserPerTier;
        trancheWeightage = _trancheWeightage;
        trancheLength = _trancheLength;
        guranteedSaleDuration = _guranteedSaleDuration;
        issuer = tx.origin;
        usdDec = usdt.decimals();
        tokenPerUsd = _tokenPerUsd;
        minAllocationPermitted = _maxTokenAllocPerUserPerTier[_maxTokenAllocPerUserPerTier.length -1]/2;
        maxAllocationPermitted = _maxTokenAllocationPermitted;
        TGE = type(uint).max;
        startTime = type(uint).max;

        // require(maxAllocationPermitted >= minAllocationPermitted, "GenIDO: Max allocation allowed should be greater or equal to min allocation");

    }

    function updateTGE(uint timestamp) external onlyIssuer {
        require(getBlockTimestamp() < TGE, "GenIDO: TGE already occurred");
        require(getBlockTimestamp() < timestamp, "GenIDO: New TGE must be in the future");

        TGE = timestamp;
    }

    // first deposit underlying tokens to contract
    function depositTokens() external onlyIssuer {
        require(!active, "GenIDO: Token is already active");
        require(IERC20(underlyingToken).transferFrom(msg.sender, address(this), totalTokenAllocation));//18
        active = true;
    }

    // This methods allows issuer to deposit tokens anytime - even after TGE
    function submitTokens(uint256 _amount) external onlyIssuer {
        require(IERC20(underlyingToken).transferFrom(msg.sender, address(this), _amount));//18
        active = true;//April25th changes// think?
    }

    function updateStartTime(uint timestamp) external onlyIssuer {
        require(getBlockTimestamp() < startTime, "GenIDO: Start time already occurred");
        require(getBlockTimestamp() < timestamp, "GenIDO: New start time must be in the future");

        startTime = timestamp;
    }

    // to end the sale and claim proceeds
    function flipIDOStatus() external onlyIssuer {
        if(active){
            require(IERC20(usdt).transfer(msg.sender, usdt.balanceOf(address(this))));//18
        }
        active = !active;
    }

    // Buying from contract directly might lead to the loss of busd submitted
    function buyAnAllocation(uint256 _pay, uint256 _staked) external {
        require(_pay > 0, "GenIDO: Payment cannot be zero");
        require(active, "GenIDO: Market is not active");
        require(getBlockTimestamp() >= startTime, "GenIDO: Start time must pass");
        uint256 pur=(_pay*tokenPerUsd)/10**usdDec;
        require(tokensPurchased+pur<=totalTokenAllocation);
        // require(tokensPurchased.add(((_pay.mul(tokenPerUsd)).div(10**18)).mul(10**tokenDec).div(10**usdDec)) <= totalTokenAllocation, "GenIDO: Sold Out");//18

        uint256 id;//id needed for guranteed participants

        Purchases memory selectedPurchase=purchases[msg.sender];

        if (_staked >= 30000 * 10**18){
            id =0;
        } else if (_staked >= 15000 * 10**18 && _staked < 30000 * 10**18){
            id =1;
        } else if(_staked >= 7500 * 10**18 && _staked < 15000 * 10**18){
            id =2;
        } else if(_staked >= 2000 * 10**18 && _staked < 7500 * 10**18){
            id =3;
        } else{
            revert("GenIDO: Invalid User");
        }

        require(selectedPurchase.tokenAllocationBought+pur >= minAllocationPermitted , "GenIDO: User min purchase violation");//6
        //following block only executes for for guranteed sale
        if (getBlockTimestamp() < startTime+guranteedSaleDuration){
            require(selectedPurchase.tokenAllocationBought+pur <= maxAllocPerUserPerTier[id], "GenIDO: User max purchase violation");//6
            tokensBought[msg.sender][1]+=pur;
            
        }
        else {
        require(selectedPurchase.tokenAllocationBought+pur <= maxAllocationPermitted, "GenIDO: Max Purchase Limit Reached");//6
        tokensBought[msg.sender][2]+=pur;
        }
        purchases[msg.sender].tokenAllocationBought += uint112(pur);
        tokensPurchased += pur;

        // payment made by User
        require(usdt.transferFrom(msg.sender, address(this), _pay));

        if(selectedPurchase.tokenAllocationBought==0)
        emit allocationBought(msg.sender, pur, true);
        else
        emit allocationBought(msg.sender, pur, false);
    }


    function getTokensSold() public view returns (uint256 tokensSold) {
         tokensSold = tokensPurchased;
    }

    function getAmountRaised() public view returns (uint256 amountRaised) {
        amountRaised = (tokensPurchased*(10**usdDec))/tokenPerUsd;
    }

    //issuer's responsibility to decide on claim amount - in case of blacklisted user or any emergency case
    function withdrawTokens(uint256 _amount) external onlyIssuer{
        require (_amount <= underlyingToken.balanceOf(address(this)), "GenIDO: Invalid amount to withdraw");
        require(underlyingToken.transfer(issuer, _amount));
    }

    //for users who bought from contract rather than web app
    function setBlackList(address[] calldata addresses, bool blackListOn) external onlyIssuer {
        require(addresses.length < 200, "GenIDO: Blacklist less than 200 at a time");

        for (uint256 i=0; i<addresses.length;) {
            blacklist[addresses[i]] = blackListOn;
            unchecked {
                 i++;
            }
        }
    }
    function redeem() public {
        require(!blacklist[msg.sender], "GenIDO: User in blacklist");
        require(getBlockTimestamp() > TGE, "GenIDO: Project TGE not occured");

        uint256 redeemablePercentage;
        Purchases memory selectedPurchase=purchases[msg.sender];
        uint256[] memory selectedTranchDurations=trancheLength;
        uint256 selectedTGE=TGE;        
        require(selectedPurchase.position < selectedTranchDurations.length, "GenIDO: All tranches fully claimed");        

        for (uint256 i=selectedPurchase.position; i<selectedTranchDurations.length ;){   // remove equal

        if (selectedTGE+selectedTranchDurations[i] <= getBlockTimestamp()) {
                redeemablePercentage += trancheWeightage[i];
                if(i==selectedTranchDurations.length-1) {
                    purchases[msg.sender].position=uint112(selectedTranchDurations.length);
                    break;
                }
            } 
        else {
                purchases[msg.sender].position=uint112(i);
                break;
            }
            unchecked { i++; }
        }
        redeemablePercentage=redeemablePercentage;
        require(redeemablePercentage > 0, "GenIDO: zero amount cannot be claimed");
        uint256 tokens = (selectedPurchase.tokenAllocationBought*redeemablePercentage)/(10**20);
        require(IERC20(underlyingToken).transfer(msg.sender, tokens));

        emit claimed(msg.sender, tokens);
    }

    function getBlockTimestamp() internal view returns (uint) {
        // solium-disable-next-line security/no-block-members
        return block.timestamp;
    }

}