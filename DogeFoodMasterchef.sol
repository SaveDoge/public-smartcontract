// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "./IERC20.sol";
import "./SafeERC20.sol";
import "./SafeMath.sol";
import "./Ownable.sol";
import "./ReentrancyGuard.sol";
import "./IERC20.sol";
import "./Interface.sol";

// MasterChef is the master of dogeFood. He can make dogeFood and he is a fair guy.
//
// Note that it's ownable and the owner wields tremendous power. The ownership
// will be transferred to a governance smart contract once dogeFood is sufficiently
// distributed and the community can show to govern itself.
//
// Have fun reading it. Hopefully it's bug-free. God bless.
contract MasterChef is Ownable, ReentrancyGuard {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    // Info of each user.
    struct UserInfo {
        uint256 amount; // How many LP tokens the user has provided.
        uint256 rewardDebt; // Reward debt. See explanation below.
        //
        // We do some fancy math here. Basically, any point in time, the amount of dogeFoods
        // entitled to a user but is pending to be distributed is:
        //
        //   pending reward = (user.amount * pool.accdogeFoodPerShare) - user.rewardDebt
        //
        // Whenever a user deposits or withdraws LP tokens to a pool. Here's what happens:
        //   1. The pool's `accDogeFoodPerShare` (and `lastRewardBlock`) gets updated.
        //   2. User receives the pending reward sent to his/her address.
        //   3. User's `amount` gets updated.
        //   4. User's `rewardDebt` gets updated.
    }
    // Info of each pool.
    struct PoolInfo {
        IERC20 lpToken;             // Address of LP token contract.
        uint256 allocPoint;         // How many allocation points assigned to this pool. dogeFoods to distribute per block.
        uint256 lastRewardBlock;    // Last block number that dogeFoods distribution occurs.
        uint256 accDogeFoodPerShare;     // Accumulated dogeFoods per share, times 1e12. See below.
        uint256 depositFee;         // Pool Deposit fee
    }

    struct NFTDetails {
        address nftAddress;
        uint256 tokenId;
    }

    // The DOGEFOOD TOKEN!
    IDogeFoodToken public dogeFood;
    // Block number when bonus DOGEFOOD period ends.
    uint256 public bonusEndBlock;
    // DOGEFOOD tokens created per block.
    uint256 public dogeFoodPerBlock;
    // Bonus muliplier for early dogeFood makers.
    uint256 public constant BONUS_MULTIPLIER = 2;
    // Info of each pool.
    PoolInfo[] public poolInfo;
    // Info of each user that stakes LP tokens.
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;
    // Lptoken amount invested on particular pool Map.
    mapping (uint256 => uint256) public lpTokenAmount;
    // Total allocation points. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint = 0;
    // The block number when DOGEFOOD mining starts.
    uint256 public startBlock;
    // The block number when DOGEFOOD mining ends.
    uint256 public endBlock;
    // Booster NFT link details
    mapping(address => mapping(uint256 => NFTDetails)) private _depositedNFT; // user => pid => nft Details;
    // Booster NFT rate based on APY will be boosted
    mapping(address => uint256) public nftBoostRate;
    // Referral contract address.
    IReferral public referral;
    // Referral commission rate in basis points.
    uint16 public referralCommissionRate = 100; // 1%
    // Max referral commission rate: 10%.
    uint16 public constant MAXIMUM_REFERRAL_COMMISSION_RATE = 1000;
    // dev Address where desposit fee will be sent
    address public devAddress;

    event Deposit(address indexed user, uint256 indexed pid, uint256 amount, uint256 fee);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event DepositNFT(address indexed user, address indexed nftAddress, uint256 _nftIndex);
    event WithdrawNFT(address indexed user, address indexed nftAddress, uint256 _nftIndex);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event AddPool(uint256 _pid, uint256 _allocPoint, address indexed _lptoken, uint256 _depositFee);
    event UpdateAlloc(uint256 _pid, uint256 allocPoint, bool _withUpdate);
    event UpdateEmissionRate(address indexed user, uint256 tokenPerBlock);
    event UpdateNFTBoostRate(address indexed user, address nftAddress, uint256 rate);
    event ReferralCommissionPaid(address indexed user, address indexed referrer, uint256 commissionAmount);

    constructor(
        IDogeFoodToken _dogeFood,
        address _boosterNFT,
        uint256 _boosterRate,
        uint256 _dogeFoodPerBlock,
        uint256 _startBlock,
        uint256 _endBlock,
        uint256 _bonusEndBlock,
        address _devAddress
    ) public {
        require(_bonusEndBlock <= _endBlock, "MasterChef: _bonusEndBlock > _endBlock");

        dogeFood = _dogeFood;
        dogeFoodPerBlock = _dogeFoodPerBlock;
        bonusEndBlock = _bonusEndBlock;
        startBlock = _startBlock;
        endBlock = _endBlock;
        devAddress = _devAddress;

        // boosterRate should be in 2 decimal.
        // for example, if we want to set 1% then pass _boosterRate as 100
        nftBoostRate[_boosterNFT] = _boosterRate;
    }

    /* ========== NFT View Functions ========== */

    function getBoost(address _account, uint256 _pid) public view returns (uint256) {
        NFTDetails memory nftDetail = _depositedNFT[_account][_pid];
        if (nftDetail.nftAddress == address(0x0)) {
            return 0;
        }

        return nftBoostRate[nftDetail.nftAddress];
    }

    function getStakedNFTDetails(address _account, uint256 _pid) public view returns (address, uint256) {
        return (_depositedNFT[_account][_pid].nftAddress, _depositedNFT[_account][_pid].tokenId);
    }


    /* ========== View Functions ========== */
    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    // Add a new lp to the pool. Can only be called by the owner.
    function add(
        uint256 _allocPoint,
        IERC20 _lpToken,
        uint256 _depositFee,
        bool _withUpdate
    ) external onlyOwner {
        require(endBlock > block.number, "MasterChef: Mining ended");
        require(_depositFee <= 1000, "deposit fee cannot be > 10%");

        if (_withUpdate) {
            massUpdatePools();
        }
        uint256 lastRewardBlock = block.number > startBlock ? block.number : startBlock;
        totalAllocPoint = totalAllocPoint.add(_allocPoint);

        poolInfo.push(
            PoolInfo({
                lpToken: _lpToken,
                allocPoint: _allocPoint,
                lastRewardBlock: lastRewardBlock,
                accDogeFoodPerShare: 0,
                depositFee: _depositFee
            })
        );
        emit AddPool(poolInfo.length - 1, _allocPoint, address(_lpToken),_depositFee);
    }

    // Update the given pool's DOGEFOOD allocation point. Can only be called by the owner.
    function set(
        uint256 _pid,
        uint256 _allocPoint,
        bool _withUpdate
    ) external onlyOwner {
        require(endBlock > block.number, "MasterChef: Mining ended");
        require(_pid < poolInfo.length, "invalid _pid");
        if (_withUpdate) {
            massUpdatePools();
        }
        totalAllocPoint = totalAllocPoint.sub(poolInfo[_pid].allocPoint).add(_allocPoint);
        poolInfo[_pid].allocPoint = _allocPoint;
        emit UpdateAlloc(_pid, _allocPoint, _withUpdate);
    }

    // Return reward multiplier over the given _from to _to block.
    function getMultiplier(uint256 _from, uint256 _to)
        public
        view
        returns (uint256)
    {
        // set range to not exceed endBlock
        if (_from > endBlock) return 0;
        _to = _to > endBlock ? endBlock : _to;

        if (_to <= bonusEndBlock) {
            // from and to within bonus period
            return _to.sub(_from).mul(BONUS_MULTIPLIER);
        } else if (_from >= bonusEndBlock) {
            // past bonus period
            return _to.sub(_from);
        } else {
            return
                // from less than bonus period to past end of bonus period
                bonusEndBlock.sub(_from).mul(BONUS_MULTIPLIER).add(
                    _to.sub(bonusEndBlock)
                );
        }
    }

    // View function to see pending DogeFoods on frontend.
    function pendingDogeFood(uint256 _pid, address _user)
        external
        view
        returns (uint256)
    {
        require(_pid < poolInfo.length, "invalid _pid");
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accDogeFoodPerShare = pool.accDogeFoodPerShare;
        uint256 lpSupply = lpTokenAmount[_pid];
        if (block.number > pool.lastRewardBlock && lpSupply != 0
            && pool.lastRewardBlock < endBlock) {
            uint256 multiplier = 
                getMultiplier(pool.lastRewardBlock, block.number);
            uint256 dogeFoodReward =
                multiplier.mul(dogeFoodPerBlock).mul(pool.allocPoint).div(totalAllocPoint);
            accDogeFoodPerShare = 
                accDogeFoodPerShare.add(dogeFoodReward.mul(1e12).div(lpSupply));
        }
        return user.amount.mul(accDogeFoodPerShare).div(1e12).sub(user.rewardDebt);
    }

    /* ========== NFT External Functions ========== */

    // Depositing of NFTs
    function depositNFT(address _nft, uint256 _tokenId, uint256 _pid) public nonReentrant {
        require(ERC721(_nft).ownerOf(_tokenId) == msg.sender, "user does not have specified NFT");

        NFTDetails memory nftDetail = _depositedNFT[msg.sender][_pid];
        require(nftDetail.nftAddress == address(0x0), "user have already boosted pool by Staking NFT");
        
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        
        updatePool(_pid);

        if (user.amount > 0) {
            uint256 pending = user.amount.mul(pool.accDogeFoodPerShare).div(1e12).sub(user.rewardDebt);
            if (pending > 0) {
                safeDogeFoodTransfer(msg.sender, pending, _pid);
            }
            user.rewardDebt = user.amount.mul(pool.accDogeFoodPerShare).div(1e12);
        }
        
        ERC721(_nft).transferFrom(msg.sender, address(this), _tokenId);

        nftDetail.nftAddress = _nft;
        nftDetail.tokenId = _tokenId;

        _depositedNFT[msg.sender][_pid] = nftDetail;

        emit DepositNFT(msg.sender, _nft, _tokenId);
    }

    // Withdrawing of NFTs
    function withdrawNFT(uint256 _pid) public nonReentrant {
        NFTDetails memory nftDetail = _depositedNFT[msg.sender][_pid];
        require(nftDetail.nftAddress != address(0x0), "user has not staked any NFT!!!");

        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];

        updatePool(_pid);

        if (user.amount > 0) {
            uint256 pending = user.amount.mul(pool.accDogeFoodPerShare).div(1e12).sub(user.rewardDebt);
            if (pending > 0) {
                safeDogeFoodTransfer(msg.sender, pending, _pid);
            }
            user.rewardDebt = user.amount.mul(pool.accDogeFoodPerShare).div(1e12);
        }

        address _nft = nftDetail.nftAddress;
        uint256 _tokenId = nftDetail.tokenId;

        nftDetail.nftAddress = address(0x0);
        nftDetail.tokenId = 0;

        _depositedNFT[msg.sender][_pid] = nftDetail;
        
        ERC721(_nft).transferFrom(address(this), msg.sender, _tokenId);

        emit WithdrawNFT(msg.sender, _nft, _tokenId);
    }


    // Update reward vairables for all pools. Be careful of gas spending!
    function massUpdatePools() public {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
    }

    // Update reward variables of the given pool to be up-to-date.
    function updatePool(uint256 _pid) public {
        require(_pid < poolInfo.length, "invalid _pid");
        PoolInfo storage pool = poolInfo[_pid];
        if (block.number <= pool.lastRewardBlock || pool.lastRewardBlock >= endBlock) {
            return;
        }
        uint256 lpSupply = lpTokenAmount[_pid];
        if (lpSupply == 0) {
            pool.lastRewardBlock = block.number;
            return;
        }
        uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);
        uint256 dogeFoodReward = multiplier.mul(dogeFoodPerBlock).mul(pool.allocPoint).div(totalAllocPoint);
        dogeFood.mint(address(this), dogeFoodReward);
        pool.accDogeFoodPerShare = pool.accDogeFoodPerShare.add(dogeFoodReward.mul(1e12).div(lpSupply));
        pool.lastRewardBlock = block.number > endBlock ? endBlock : block.number;
    }

    // Deposit LP tokens to MasterChef for DOGEFOOD allocation.
    function deposit(uint256 _pid, uint256 _amount, address _referrer) external nonReentrant {
        require(endBlock > block.number, "MasterChef: Mining ended");
        require(_pid < poolInfo.length, "invalid _pid");
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        updatePool(_pid);

        if (_amount > 0 && address(referral) != address(0) && _referrer != address(0) && _referrer != msg.sender) {
            referral.recordReferral(msg.sender, _referrer);
        }

        if (user.amount > 0) {
            uint256 pending = user.amount.mul(pool.accDogeFoodPerShare).div(1e12).sub(user.rewardDebt);
            if (pending > 0) {
                safeDogeFoodTransfer(msg.sender, pending, _pid);
            }
        }

        uint256 fee;
        if (_amount > 0) {
            // modified to handle fee on transfer tokens
            uint256 before = pool.lpToken.balanceOf(address(this));
            pool.lpToken.safeTransferFrom(msg.sender, address(this), _amount);
            _amount = pool.lpToken.balanceOf(address(this)).sub(before);

            fee = _amount.mul(pool.depositFee).div(10000);
            if (fee > 0) {
                pool.lpToken.safeTransfer(devAddress, fee);
            }
            user.amount = user.amount.add(_amount.sub(fee));
            lpTokenAmount[_pid] = lpTokenAmount[_pid].add(_amount.sub(fee));
        }

        user.rewardDebt = user.amount.mul(pool.accDogeFoodPerShare).div(1e12);
        emit Deposit(msg.sender, _pid, _amount.sub(fee), fee);
    }

    // Withdraw LP tokens from MasterChef.
    function withdraw(uint256 _pid, uint256 _amount) external nonReentrant {
        require(_pid < poolInfo.length, "invalid _pid");
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        require(user.amount >= _amount, "withdraw: not good");
        updatePool(_pid);
        uint256 pending =
            user.amount.mul(pool.accDogeFoodPerShare).div(1e12).sub(user.rewardDebt);

        if (pending > 0) {
            safeDogeFoodTransfer(msg.sender, pending, _pid);
        }

        if (_amount > 0) {
            user.amount = user.amount.sub(_amount);
            lpTokenAmount[_pid] = lpTokenAmount[_pid].sub(_amount);
            pool.lpToken.safeTransfer(address(msg.sender), _amount);
        }
        
        user.rewardDebt = user.amount.mul(pool.accDogeFoodPerShare).div(1e12);
        
        emit Withdraw(msg.sender, _pid, _amount);
    }

    // Withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdraw(uint256 _pid) nonReentrant external {
        require(_pid < poolInfo.length, "invalid _pid");
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        uint256 amount = user.amount;
        lpTokenAmount[_pid] = lpTokenAmount[_pid].sub(amount);
        user.amount = 0;
        user.rewardDebt = 0;
        emit EmergencyWithdraw(msg.sender, _pid, amount);
        pool.lpToken.safeTransfer(address(msg.sender), amount);
    }

    // Safe dogeFood transfer function, just in case if rounding error causes pool to not have enough DogeFoods.
    function safeDogeFoodTransfer(address _to, uint256 _amount, uint256 _pid) internal {
        uint256 boost = 0;

        uint256 dogeFoodBal = dogeFood.balanceOf(address(this));
        if (_amount > dogeFoodBal) {
            dogeFood.transfer(_to, dogeFoodBal);
        } else {
            dogeFood.transfer(_to, _amount);
        }

        boost = getBoost(_to, _pid).mul(_amount).div(10000);
        payReferralCommission(msg.sender, _amount);
        if (boost > 0) dogeFood.mint(_to, boost);
    }

    /* ========== Set Variable Functions ========== */

    function updateEmissionRate(uint256 _dogeFoodPerBlock) public onlyOwner {
        massUpdatePools();
        dogeFoodPerBlock = _dogeFoodPerBlock;
        emit UpdateEmissionRate(msg.sender, _dogeFoodPerBlock);
    }

    function setNftBoostRate(address _nftAddress, uint256 _rate) public onlyOwner {
        nftBoostRate[_nftAddress] = _rate;
        emit UpdateNFTBoostRate(msg.sender, _nftAddress, _rate);
    }

    function setDevAddress(address _devAddress) public onlyOwner {
        require(_devAddress != address(0x0), "_devAddress address should be valid address");
        devAddress = _devAddress;
    }

    function setDepositFee(uint256 _pid, uint256 _depositFee) public onlyOwner {
        require(_depositFee <= 1000, "deposit Fee cannot be more then 10%");
        poolInfo[_pid].depositFee = _depositFee;
    }

    function setReferralAddress(IReferral _referral) public onlyOwner {

        referral = _referral;
    }

    function setReferralCommissionRate(uint16 _referralCommissionRate) public onlyOwner {
        require(_referralCommissionRate <= MAXIMUM_REFERRAL_COMMISSION_RATE, "setReferralCommissionRate: invalid referral commission rate basis points");
        referralCommissionRate = _referralCommissionRate;
    }

    /* ========== Internal Functions ========== */

    // Pay referral commission to the referrer who referred this user
    function payReferralCommission(address _user, uint256 _pending) internal {
        if (address(referral) != address(0) && referralCommissionRate > 0) {
            address referrer = referral.getReferrer(_user);
            uint256 commissionAmount = _pending.mul(referralCommissionRate).div(10000);

            if (referrer != address(0) && commissionAmount > 0) {
                dogeFood.mint(referrer, commissionAmount);
                referral.recordReferralCommission(referrer, commissionAmount);
                emit ReferralCommissionPaid(_user, referrer, commissionAmount);
            }
        }
    }
}
