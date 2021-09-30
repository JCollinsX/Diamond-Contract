// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "./owner/Operator.sol";

contract FishRewardPool is Destructor {

    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    address public DAO = 0x1C3dF661182c1f9cc8afE226915e5f91E93d1A6f;

    struct UserInfo {
        uint256 amount;     // How many LP tokens the user has provided.
        uint256 rewardDebt; // Reward debt.
    }

    struct PoolInfo {
        IERC20 lpToken;          // Address of LP token contract.
        uint256 allocPoint;      // How many allocation points assigned to this pool. FISH to distribute per block.
        uint256 lastRewardBlock; // Last block number that FISH distribution occurs.
        uint256 accFishPerShare; // Accumulated FISH per share, times 1e18.
        bool isStarted;          // Has lastRewardBlock passed?
    }

    uint256 public version = 1;
    uint256 public depositFeePercent = 0;
    uint256 public withdrawFeePercent = 2;
    IERC20 public FISH;

    PoolInfo[] public poolInfo;

    mapping(uint256 => mapping(address => UserInfo)) public userInfo;

    uint256 public totalAllocPoint = 0;             // Total allocation points. Must be the sum of all allocation points in all pools.
    uint256 public startBlock;                      // The block number when FISH minting starts.
    uint256 public endBlock;                        // The block number when FISH minting ends.
    uint256 public constant BLOCKS_PER_DAY = 28800; // 86400 / 3;
    uint256 public rewardDuration = 365;            // Days.
    uint256 public totalRewards = 440 ether;
    uint256 public rewardPerBlock;
    bool public isMintStarted = false;

    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event RewardPaid(address indexed user, uint256 amount);


    constructor(address _FISH, uint256 _startBlock) public {
        require(block.number < _startBlock, "FishRewardPool.constructor(): The current block is after the specified start block.");
        if (_FISH != address(0)) FISH = IERC20(_FISH);
        startBlock = _startBlock;
        endBlock = startBlock.add(BLOCKS_PER_DAY.mul(rewardDuration));
        rewardPerBlock = totalRewards.div(endBlock.sub(startBlock));
    }

    function checkPoolDuplicate(IERC20 _lpToken) internal view {
        uint256 length = poolInfo.length;
        require(length < 6, "FishRewardPool.checkPoolDuplicate(): Pool size exceeded.");
        for (uint256 pid = 0; pid < length; ++pid) {
            require(poolInfo[pid].lpToken != _lpToken, "FishRewardPool.checkPoolDuplicate(): Found duplicate token in pool.");
        }
    }

    // Add a new lp token to the pool. Can only be called by the owner.
    function add(uint256 _allocPoint, IERC20 _lpToken, bool _withUpdate, uint256 _lastRewardBlock) external onlyOperator {
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
            accFishPerShare : 0,
            isStarted : _isStarted
            }));
        if (_isStarted) {
            totalAllocPoint = totalAllocPoint.add(_allocPoint);
        }
    }

    // Update the given pool's FISH allocation point. Can only be called by the owner.
    function set(uint256 _pid, uint256 _allocPoint) public {
        require(isOperator() || _msgSender() == owner(), "invalid operator");
        massUpdatePools();
        PoolInfo storage pool = poolInfo[_pid];
        if (pool.isStarted) {
            totalAllocPoint = totalAllocPoint.sub(pool.allocPoint).add(_allocPoint);
        }
        pool.allocPoint = _allocPoint;
    }

    // Return accumulated rewards over the given _from to _to block.
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

    // View function to see pending FISH on frontend.
    function pendingReward(uint256 _pid, address _user) external view returns (uint256) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accFishPerShare = pool.accFishPerShare;
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (block.number > pool.lastRewardBlock && lpSupply != 0) {
            uint256 _generatedReward = getGeneratedReward(pool.lastRewardBlock, block.number);
            uint256 _FISHReward = _generatedReward.mul(pool.allocPoint).div(totalAllocPoint);
            accFishPerShare = accFishPerShare.add(_FISHReward.mul(1e18).div(lpSupply));
        }
        return user.amount.mul(accFishPerShare).div(1e18).sub(user.rewardDebt);
    }

    // Update reward variables for all pools. Be careful of gas spending!
    function massUpdatePools() public {
        uint256 length = poolInfo.length;
        require(length < 6, "FishRewardPool.massUpdatePools(): Pool size exceeded.");
        for (uint256 pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
    }

    // Update reward variables of the given pool to be up-to-date.
    function updatePool(uint256 _pid) public {
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
            uint256 _FISHReward = _generatedReward.mul(pool.allocPoint).div(totalAllocPoint);
            pool.accFishPerShare = pool.accFishPerShare.add(_FISHReward.mul(1e18).div(lpSupply));
        }
        pool.lastRewardBlock = block.number;
    }

    // Deposit tokens.
    function deposit(uint256 _pid, uint256 _amount) external {
        address _sender = msg.sender;
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_sender];
        updatePool(_pid);
        if (user.amount > 0) {
            uint256 _pending = user.amount.mul(pool.accFishPerShare).div(1e18).sub(user.rewardDebt);
            if (_pending > 0) {
                safeFishTransfer(_sender, _pending);
                emit RewardPaid(_sender, _pending);
            }
        }
        if (_amount > 0) {
            uint feeToDAO = 0;
            feeToDAO = _amount.mul(depositFeePercent).div(100); // 2% fee when deposit in version 2.
            if(feeToDAO > 0) pool.lpToken.safeTransferFrom(_sender, DAO, feeToDAO);
            pool.lpToken.safeTransferFrom(_sender, address(this), _amount.sub(feeToDAO));

            user.amount = user.amount.add(_amount.sub(feeToDAO));
        }
        user.rewardDebt = user.amount.mul(pool.accFishPerShare).div(1e18);
        emit Deposit(_sender, _pid, _amount);
    }

    // Withdraw tokens.
    function withdraw(uint256 _pid, uint256 _amount) external {
        address _sender = msg.sender;
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_sender];
        require(user.amount >= _amount, "FishRewardPool.withdraw(): User amount less than withdrawal amount.");
        updatePool(_pid);
        uint256 _pending = user.amount.mul(pool.accFishPerShare).div(1e18).sub(user.rewardDebt);
        if (_pending > 0) {
            safeFishTransfer(_sender, _pending);
            emit RewardPaid(_sender, _pending);
        }
        if (_amount > 0) {
            uint256 FeeToDAO = 0;
            FeeToDAO = _amount.mul(withdrawFeePercent).div(100);     // Users pay 2% fee to DAO when withdraw in version 1.
            if(FeeToDAO > 0) pool.lpToken.safeTransfer(DAO, FeeToDAO);
            pool.lpToken.safeTransfer(_sender, _amount.sub(FeeToDAO));
            user.amount = user.amount.sub(_amount);
        }
        user.rewardDebt = user.amount.mul(pool.accFishPerShare).div(1e18);
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

    // Safe FISH transfer function, just in case if rounding error causes pool to not have enough FISH.
    function safeFishTransfer(address _to, uint256 _amount) internal {
        uint256 _FISHBal = FISH.balanceOf(address(this));
        if (_FISHBal > 0) {
            if (_amount > _FISHBal) {
                FISH.safeTransfer(_to, _FISHBal);
            } else {
                FISH.safeTransfer(_to, _amount);
            }
        }
    }

    function governanceRecoverUnsupported(IERC20 _token, uint256 amount, address to) external onlyOperator {
        if (block.number < endBlock + BLOCKS_PER_DAY * 180) {
            // Do not allow to drain lpToken if less than 180 days after farming.
            require(_token != FISH, "FishRewardPool.governanceRecoverUnsupported(): Not a fish token.");
            uint256 length = poolInfo.length;
            require(length < 6, "FishRewardPool.governanceRecoverUnsupported(): Pool size exceeded.");
            for (uint256 pid = 0; pid < length; ++pid) {
                PoolInfo storage pool = poolInfo[pid];
                require(_token != pool.lpToken, "FishRewardPool.governanceRecoverUnsupported(): Skipping liquidity provider token.");
            }
        }
        _token.safeTransfer(to, amount);
    }

    // Update pool versioning.
    function changePoolVersion() external onlyOwner {
        require(block.number >= startBlock.add(BLOCKS_PER_DAY.mul(8)), "FishRewardPool.changePoolVersion(): not ready version 2.");
        require(version == 1, "FishRewardPool.changePoolVersion(): Already updated version.");
        require(poolInfo.length > 4, "FishRewardPool.changePoolVersion(): Not enough pools.");
        version = 2;
        set(0, 3000);
        set(1, 3000);
        set(2, 6000);
        set(3, 1000);
        set(4, 0);
        depositFeePercent = 2;
        withdrawFeePercent = 0;
    }

    function getPoolStatus() external view returns(uint256) {
        uint256 status;
        if(block.number <= startBlock) status = 0;
        else if(block.number > endBlock) status = 2;
        else status = 1;
        return status;
    }

    function isReadyPoolV2() external view returns(bool) {
        if(version == 2) return false;
        if(block.number >= startBlock.add(BLOCKS_PER_DAY.mul(8))) return true;
        return false;
    }
}
