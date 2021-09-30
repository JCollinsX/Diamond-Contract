// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "./owner/Operator.sol";
import "./utils/ContractGuard.sol";
import "./interfaces/IEpoch.sol";
import "./interfaces/ITreasury.sol";
import "./interfaces/IBasisAsset.sol";

contract ShareWrapper {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    IERC20 public FISH;
    uint256 private _totalSupply;
    mapping(address => uint256) private _balances;

    function totalSupply() public view returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) public view returns (uint256) {
        return _balances[account];
    }

    function stake(uint256 amount) public virtual {
        _totalSupply = _totalSupply.add(amount);
        _balances[msg.sender] = _balances[msg.sender].add(amount);
        FISH.safeTransferFrom(msg.sender, address(this), amount);
    }

    function withdraw(uint256 amount) public virtual {
        uint256 directorShare = _balances[msg.sender];
        require(directorShare >= amount, "Boardroom.withdraw(): Share amount less than withdrawal amount.");
        _totalSupply = _totalSupply.sub(amount);
        _balances[msg.sender] = directorShare.sub(amount);
    }
}


contract Boardroom is ShareWrapper, ContractGuard, Destructor {
    using Address for address;
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    // Data structures.

    struct Boardseat {
        uint256 lastSnapshotIndex;
        uint256 rewardEarned;
        uint256 epochTimerStart;
    }

    struct BoardSnapshot {
        uint256 time;
        uint256 rewardReceived;
        uint256 rewardPerShare;
    }

    // State variables.

    bool public initialized = false;

    // Governance.

    address public DAO = 0x1C3dF661182c1f9cc8afE226915e5f91E93d1A6f;

    IERC20 public CHIP;
    ITreasury public treasury;
    mapping(address => Boardseat) public directors;
    BoardSnapshot[] public boardHistory;
    uint256 public withdrawLockupEpochs;
    uint256 public rewardLockupEpochs;

    // Events.

    event Initialized(address indexed executor, uint256 at);
    event Staked(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event RewardPaid(address indexed user, uint256 reward);
    event RewardAdded(address indexed user, uint256 reward);

    // Modifiers.

    modifier directorExists {
        require(balanceOf(msg.sender) > 0, "Boardroom.directorExists(): The director does not exist.");
        _;
    }

    modifier updateReward(address director) {
        if (director != address(0)) {
            Boardseat memory seat = directors[director];
            seat.rewardEarned = earned(director);
            seat.lastSnapshotIndex = latestSnapshotIndex();
            directors[director] = seat;
        }
        _;
    }

    modifier notInitialized {
        require(!initialized, "Boardroom: already initialized");
        _;
    }

    function initialize(
        IERC20 _CHIP,
        IERC20 _FISH,
        ITreasury _treasury
    ) external onlyOperator notInitialized {
        CHIP = _CHIP;
        FISH = _FISH;
        treasury = _treasury;
        boardHistory.push(BoardSnapshot({time: block.number, rewardReceived: 0, rewardPerShare: 0}));
        withdrawLockupEpochs = 6; // Lock for 6 epochs (36h) before release withdraw.
        rewardLockupEpochs = 3; // Lock for 3 epochs (18h) before release claimReward.
        initialized = true;
        emit Initialized(msg.sender, block.number);
    }

    function setLockUp(uint256 _withdrawLockupEpochs, uint256 _rewardLockupEpochs) external onlyOperator {
        require(_withdrawLockupEpochs >= _rewardLockupEpochs && _withdrawLockupEpochs <= 56, "Boardroom.setLockUp(): Out of range."); // <= 2 week.
        withdrawLockupEpochs = _withdrawLockupEpochs;
        rewardLockupEpochs = _rewardLockupEpochs;
    }

    function latestSnapshotIndex() public view returns (uint256) {
        return boardHistory.length.sub(1);
    }

    function getLatestSnapshot() internal view returns (BoardSnapshot memory) {
        return boardHistory[latestSnapshotIndex()];
    }

    function getLastSnapshotIndexOf(address director) public view returns (uint256) {
        return directors[director].lastSnapshotIndex;
    }

    function getLastSnapshotOf(address director) internal view returns (BoardSnapshot memory) {
        return boardHistory[getLastSnapshotIndexOf(director)];
    }

    function canWithdraw(address director) external view returns (bool) {
        return directors[director].epochTimerStart.add(withdrawLockupEpochs) <= treasury.epoch();
    }

    function canClaimReward(address director) external view returns (bool) {
        return directors[director].epochTimerStart.add(rewardLockupEpochs) <= treasury.epoch();
    }

    function epoch() external view returns (uint256) {
        return treasury.epoch();
    }

    function nextEpochPoint() external view returns (uint256) {
        return treasury.nextEpochPoint();
    }

    function getEthPrice() external view returns (uint256) {
        return treasury.getEthPrice();
    }

    // Director getters.

    function rewardPerShare() external view returns (uint256) {
        return getLatestSnapshot().rewardPerShare;
    }

    function earned(address director) public view returns (uint256) {
        uint256 latestRPS = getLatestSnapshot().rewardPerShare;
        uint256 storedRPS = getLastSnapshotOf(director).rewardPerShare;
        return balanceOf(director).mul(latestRPS.sub(storedRPS)).div(1e18).add(directors[director].rewardEarned);
    }

    // Mutators.

    function stake(uint256 amount) public override onlyOneBlock updateReward(msg.sender) {
        require(amount > 0, "Boardroom.stake(): Cannot stake 0.");
        directors[msg.sender].epochTimerStart = treasury.epoch(); // Reset timer.
        super.stake(amount);
        emit Staked(msg.sender, amount);
    }

    function withdraw(uint256 amount) public override onlyOneBlock directorExists updateReward(msg.sender) {
        require(amount > 0, "Boardroom.withdraw(): Cannot withdraw 0.");
        require(directors[msg.sender].epochTimerStart.add(withdrawLockupEpochs) <= treasury.epoch(), "Boardroom.withdraw(): Still in withdraw lockup.");
        claimReward();
        uint256 ethPrice = treasury.getEthPrice();
        uint256 feeToDAO = 10; // 10% withdraw fee when chip price is below 1.05 eth.
        if (ethPrice >= 1.05 ether) feeToDAO = 2; // Otherwise 2% fee.
        uint256 feeAmount = amount.mul(feeToDAO).div(100);
        FISH.safeTransfer(msg.sender, amount.sub(feeAmount));
        FISH.safeTransfer(DAO, feeAmount);
        super.withdraw(amount);
        emit Withdrawn(msg.sender, amount);
    }

    function exit() external {
        withdraw(balanceOf(msg.sender));
    }

    function claimReward() public updateReward(msg.sender) {
        uint256 reward = directors[msg.sender].rewardEarned;
        if (reward > 0) {
            require(directors[msg.sender].epochTimerStart.add(rewardLockupEpochs) <= treasury.epoch(), "Boardroom.claimReward(): Still in reward lockup.");
            directors[msg.sender].epochTimerStart = treasury.epoch(); // Reset timer.
            directors[msg.sender].rewardEarned = 0;
            CHIP.safeTransfer(msg.sender, reward);
            emit RewardPaid(msg.sender, reward);
        }
    }

    function allocateSeigniorage(uint256 amount) external onlyOneBlock onlyOperator {
        require(amount > 0, "Boardroom.allocateSeigniorage(): Cannot allocate 0.");
        require(totalSupply() > 0, "Boardroom.allocateSeigniorage(): Cannot allocate when total supply is 0.");
        uint256 prevRPS = getLatestSnapshot().rewardPerShare;
        uint256 nextRPS = prevRPS.add(amount.mul(1e18).div(totalSupply()));
        boardHistory.push(BoardSnapshot({time: block.number, rewardReceived: amount, rewardPerShare: nextRPS}));
        CHIP.safeTransferFrom(msg.sender, address(this), amount);
        emit RewardAdded(msg.sender, amount);
    }

    function governanceRecoverUnsupported(
        IERC20 _token,
        uint256 _amount,
        address _to
    ) external onlyOperator {
        require(address(_token) != address(CHIP), "Boardroom.governanceRecoverUnsupported(): Not a chip token.");
        require(address(_token) != address(FISH), "Boardroom.governanceRecoverUnsupported(): Not a fish token.");
        _token.safeTransfer(_to, _amount);
    }
}
