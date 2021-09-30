// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

import "./owner/Operator.sol";

// Note: This pool has no minter key of CHIPs (rewards). Instead, the governance will call
//       CHIPs distributeReward method and send reward to this pool at the beginning.

contract ChipRewardPool is Destructor, ReentrancyGuard {

    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    address public DAO = 0x1C3dF661182c1f9cc8afE226915e5f91E93d1A6f;


    struct UserInfo {
        uint256 amount;     // How many LP tokens the user has provided.
        uint256 rewardDebt; // Reward debt.
    }

    struct PoolInfo {
        IERC20 lpToken;           // Address of LP token contract.
        uint256 allocPoint;       // How many allocation points assigned to this pool. CHIPs to distribute per block.
        uint256 lastRewardBlock;  // Last block number that CHIPs distribution occurs.
        uint256 accChipsPerShare; // Accumulated CHIPs per share, times 1e18.
        bool isStarted;           // Has lastRewardBlock passed?
    }

    IERC20 public CHIPS;

    PoolInfo[] public poolInfo;

    mapping(uint256 => mapping(address => UserInfo)) public userInfo;

    uint256 public totalAllocPoint = 0;             // Total allocation points. Must be the sum of all allocation points in all pools.
    uint256 public startBlock;                      // The block number when CHIPS minting starts.
    uint256 public endBlock;                        // The block number when CHIPS minting ends.
    uint256 public timeLockBlock;
    uint256 public constant BLOCKS_PER_DAY = 28800; // 86400 / 3;
    uint256 public rewardDuration = 10;             // Days.
    uint256 public totalRewards = 50 ether;
    uint256 public rewardPerBlock;


    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event RewardPaid(address indexed user, uint256 amount);


    constructor(address _CHIPS, uint256 _startBlock) public {
        require(block.number < _startBlock, "ChipRewardPool.constructor(): The current block is after the specified start block.");
        if (_CHIPS != address(0)) CHIPS = IERC20(_CHIPS);
        startBlock = _startBlock;
        endBlock = startBlock.add(BLOCKS_PER_DAY.mul(rewardDuration));
        rewardPerBlock = totalRewards.div(endBlock.sub(startBlock));
        timeLockBlock = startBlock.add(BLOCKS_PER_DAY.mul(rewardDuration.add(1)));
    }

    function checkPoolDuplicate(IERC20 _lpToken) internal view {
        uint256 length = poolInfo.length;
        require(length < 6, "ChipRewardPool.checkPoolDuplicate(): Pool size exceeded.");
        for (uint256 pid = 0; pid < length; ++pid) {
            require(poolInfo[pid].lpToken != _lpToken, "ChipRewardPool.checkPoolDuplicate(): Found duplicate token in pool.");
        }
    }

    // Add a new lp token to the pool. Can only be called by the owner. can add only 5 lp token.
    function add(uint256 _allocPoint, IERC20 _lpToken, bool _withUpdate, uint256 _lastRewardBlock) external onlyOperator {
        require(poolInfo.length < 5, "ChipRewardPool: can't add pool anymore");
        checkPoolDuplicate(_lpToken);
        if (_withUpdate) {
            massUpdatePools();
        }
        if (block.number < startBlock) {
            // The chef is sleeping.
            if (_lastRewardBlock == 0) {
                _lastRewardBlock = startBlock;
            } else {
                if (_lastRewardBlock < startBlock) {
                    _lastRewardBlock = startBlock;
                }
            }
        } else {
            // The chef is cooking.
            if (_lastRewardBlock == 0 || _lastRewardBlock < block.number) {
                _lastRewardBlock = block.number;
            }
        }
        bool _isStarted =
        (_lastRewardBlock <= startBlock) ||
        (_lastRewardBlock <= block.number);
        poolInfo.push(PoolInfo({
            lpToken : _lpToken,
            allocPoint : _allocPoint,
            lastRewardBlock : _lastRewardBlock,
            accChipsPerShare : 0,
            isStarted : _isStarted
            }));
        if (_isStarted) {
            totalAllocPoint = totalAllocPoint.add(_allocPoint);
        }
    }

    // Update the given pool's CHIPs allocation point. Can only be called by the owner.
    function set(uint256 _pid, uint256 _allocPoint) public onlyOperator {
        require(block.number > timeLockBlock, "ChipRewardPool: Locked");
        massUpdatePools();
        PoolInfo storage pool = poolInfo[_pid];
        if (pool.isStarted) {
            totalAllocPoint = totalAllocPoint.sub(pool.allocPoint).add(
                _allocPoint
            );
        }
        pool.allocPoint = _allocPoint;
    }

    // Return accumulate rewards over the given _from to _to block.
    function getGeneratedReward(uint256 _from, uint256 _to) public view returns (uint256) {
        if (_from >= _to) return 0;
        if (_to <= startBlock) {
            return 0;
        } else if (_to >= endBlock) {
            if (_from >= endBlock) {
                return 0;
            } else if (_from <= startBlock) {
                return rewardPerBlock.mul(endBlock.sub(startBlock));
            } else {
                return rewardPerBlock.mul(endBlock.sub(_from));
            }
        } else {
            if (_from <= startBlock) {
                return rewardPerBlock.mul(_to.sub(startBlock));
            } else {
                return rewardPerBlock.mul(_to.sub(_from));
            }
        }
    }

    // View function to see pending CHIPs.
    function pendingReward(uint256 _pid, address _user) external view returns (uint256) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accChipsPerShare = pool.accChipsPerShare;
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (block.number > pool.lastRewardBlock && lpSupply != 0) {
            uint256 _generatedReward = getGeneratedReward(pool.lastRewardBlock, block.number);
            uint256 _CHIPSReward = _generatedReward.mul(pool.allocPoint).div(totalAllocPoint);
            accChipsPerShare = accChipsPerShare.add(_CHIPSReward.mul(1e18).div(lpSupply));
        }
        return user.amount.mul(accChipsPerShare).div(1e18).sub(user.rewardDebt);
    }

    // Update reward variables for all pools. Be careful of gas spending!
    function massUpdatePools() internal {
        uint256 length = poolInfo.length;
        require(length < 6, "ChipRewardPool.massUpdatePools(): Pool size exceeded.");
        for (uint256 pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
    }

    // Update reward variables of the given pool to be up-to-date.
    function updatePool(uint256 _pid) internal {
        PoolInfo storage pool = poolInfo[_pid];
        if (block.number <= pool.lastRewardBlock) {
            return;
        }
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (lpSupply == 0) {
            pool.lastRewardBlock = block.number;
            return;
        }
        if (!pool.isStarted) {
            pool.isStarted = true;
            totalAllocPoint = totalAllocPoint.add(pool.allocPoint);
        }
        if (totalAllocPoint > 0) {
            uint256 _generatedReward = getGeneratedReward(pool.lastRewardBlock, block.number);
            uint256 _CHIPSReward = _generatedReward.mul(pool.allocPoint).div(totalAllocPoint);
            pool.accChipsPerShare = pool.accChipsPerShare.add(_CHIPSReward.mul(1e18).div(lpSupply));
        }
        pool.lastRewardBlock = block.number;
    }

    // Deposit tokens.
    function deposit(uint256 _pid, uint256 _amount) external nonReentrant {
        address _sender = msg.sender;
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_sender];
        updatePool(_pid);
        if (user.amount > 0) {
            uint256 _pending = user.amount.mul(pool.accChipsPerShare).div(1e18).sub(user.rewardDebt);
            if (_pending > 0) {
                safeChipsTransfer(_sender, _pending);
                emit RewardPaid(_sender, _pending);
            }
        }
        if (_amount > 0) {
            uint256 FeeToDAO = 0;
            if(_pid != 4){
                // In case of BNB, BUSD, BTD, BTS pool, users have to pay 1% fee when they deposit.
                FeeToDAO = _amount.div(100);
            }
            if(FeeToDAO > 0) pool.lpToken.safeTransferFrom(_sender, DAO, FeeToDAO);
            pool.lpToken.safeTransferFrom(_sender, address(this), _amount.sub(FeeToDAO));
            user.amount = user.amount.add(_amount.sub(FeeToDAO));
        }
        user.rewardDebt = user.amount.mul(pool.accChipsPerShare).div(1e18);
        emit Deposit(_sender, _pid, _amount);
    }

    // Withdraw tokens.
    function withdraw(uint256 _pid, uint256 _amount) external nonReentrant {
        address _sender = msg.sender;
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_sender];
        require(user.amount >= _amount, "ChipRewardPool.withdraw(): User amount less than withdrawal amount.");
        updatePool(_pid);
        uint256 _pending = user.amount.mul(pool.accChipsPerShare).div(1e18).sub(user.rewardDebt);
        if (_pending > 0) {
            safeChipsTransfer(_sender, _pending);
            emit RewardPaid(_sender, _pending);
        }
        if (_amount > 0) {
            uint256 FeeToDAO = 0;
            if(_pid == 4){
                // In case of CHIP/BNB pool, users have to pay 3% fee when they withdraw.
                FeeToDAO = _amount.mul(3).div(100);
            }
            if(FeeToDAO > 0) pool.lpToken.safeTransfer(DAO, FeeToDAO);
            pool.lpToken.safeTransfer(_sender, _amount.sub(FeeToDAO));
            user.amount = user.amount.sub(_amount);
        }
        user.rewardDebt = user.amount.mul(pool.accChipsPerShare).div(1e18);
        emit Withdraw(_sender, _pid, _amount);
    }

    // Withdraw without caring about rewards. Emergency only.
    function emergencyWithdraw(uint256 _pid) external {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        uint256 _amount = user.amount;
        user.amount = 0;
        user.rewardDebt = 0;
        pool.lpToken.safeTransfer(msg.sender, _amount);
        emit EmergencyWithdraw(msg.sender, _pid, _amount);
    }

    // Safe CHIPs transfer function, just in case if rounding error causes pool to not have enough CHIPs.
    function safeChipsTransfer(address _to, uint256 _amount) internal {
        uint256 _CHIPSBal = CHIPS.balanceOf(address(this));
        if (_CHIPSBal > 0) {
            if (_amount > _CHIPSBal) {
                CHIPS.safeTransfer(_to, _CHIPSBal);
            } else {
                CHIPS.safeTransfer(_to, _amount);
            }
        }
    }

    function governanceRecoverUnsupported(IERC20 _token, uint256 amount, address to) external onlyOperator {
        require(block.number > timeLockBlock, "ChipRewardPool: locked");
        if (block.number < endBlock + BLOCKS_PER_DAY * 180) {
            // Do not allow to drain lpToken if less than 180 days after farming.
            require(_token != CHIPS, "ChipRewardPool.governanceRecoverUnsupported(): Not a chip token.");
            uint256 length = poolInfo.length;
            require(length < 6, "ChipRewardPool.governanceRecoverUnsupported(): Pool size exceeded.");
            for (uint256 pid = 0; pid < length; ++pid) {
                PoolInfo storage pool = poolInfo[pid];
                require(_token != pool.lpToken, "ChipRewardPool.governanceRecoverUnsupported(): Skipping liquidity provider token.");
            }
        }
        _token.safeTransfer(to, amount);
    }

    function getPoolStatus() external view returns(uint256) {
        uint256 status;
        if(block.number <= startBlock) status = 0;
        else if(block.number > endBlock) status = 2;
        else status = 1;
        return status;
    }
}
