// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";

import "./owner/Operator.sol";

contract Fish is ERC20Burnable, Destructor {

    using SafeMath for uint256;

    address public teamFund = 0x7C593d2C99c75495E435D423740Dfa72123e2483;
    address public daoFund = 0x1C3dF661182c1f9cc8afE226915e5f91E93d1A6f;

    // Total max supply 600 fish.
    uint256 public constant FARMING_POOL_REWARD_ALLOCATION = 440 ether;
    uint256 public constant TEAM_FUND_POOL_ALLOCATION = 60 ether;
    uint256 public constant DAO_FUND_POOL_ALLOCATION = 50 ether;
    uint256 public constant CHIPSWAP_ALLOCATION = 50 ether;         // Allocated by treasury contract automatically to chipswap mechanism 50/365/24 fish per hour.
    uint256 public constant VESTING_DURATION = 365 days;
    uint256 public startTime;                                       // Vesting starts from contract creation time.
    uint256 public endTime;
    uint256 public teamFundRewardRate = TEAM_FUND_POOL_ALLOCATION / VESTING_DURATION;
    uint256 public daoFundRewardRate = DAO_FUND_POOL_ALLOCATION / VESTING_DURATION;
    address public chipswapFund;
    uint256 public teamFundLastClaimed;
    uint256 public daoFundLastClaimed;
    bool public rewardPoolDistributed = false;
    bool public chipSwapDistributed = false;


    constructor() public ERC20("ChipShop Share", "FISH") {
        startTime = block.timestamp;
        endTime = startTime.add(VESTING_DURATION);
        teamFundLastClaimed = startTime;
        daoFundLastClaimed = startTime;
        _mint(daoFund, 0.1 ether); // Send 0.1 ether to deployer.
    }


    function setChipSwapFund(address _chipswapFund) external onlyOperator {
        require(_chipswapFund != address(0x0), "FishToken.setChipSwapFund(): Invalid chipswap fund address.");
        chipswapFund = _chipswapFund;
    }

    function distributeChipSwapFund() external onlyOperator {
        require(!chipSwapDistributed, "FishToken.distributeChipSwapFund(): Already distributed to chipswap mechanism.");
        require(chipswapFund != address(0x0), "FishToken.distributeChipSwapFund(): Invalid chipswap fund address.");
        chipSwapDistributed = true;
        _mint(chipswapFund, CHIPSWAP_ALLOCATION);
    }

    function unclaimedTeamFund() public view returns (uint256 _pending) {
        uint256 _now = block.timestamp;
        if (_now > endTime) _now = endTime;
        if (teamFundLastClaimed >= _now) return 0;
        _pending = _now.sub(teamFundLastClaimed).mul(teamFundRewardRate);
    }

    function unclaimedDaoFund() public view returns (uint256 _pending) {
        uint256 _now = block.timestamp;
        if (_now > endTime) _now = endTime;
        if (daoFundLastClaimed >= _now) return 0;
        _pending = _now.sub(daoFundLastClaimed).mul(daoFundRewardRate);
    }

    function claimRewards() external {
        uint256 _pending = unclaimedTeamFund();
        if (_pending > 0 && teamFund != address(0)) {
            _mint(teamFund, _pending);
            teamFundLastClaimed = block.timestamp;
        }
        _pending = unclaimedDaoFund();
        if (_pending > 0 && daoFund != address(0)) {
            _mint(daoFund, _pending);
            daoFundLastClaimed = block.timestamp;
        }
    }

    function distributeReward(address farmingIncentiveFund) external onlyOperator {
        require(!rewardPoolDistributed, "FishToken.distributeReward(): Can distribute only once.");
        require(farmingIncentiveFund != address(0), "FishToken.distributeReward(): Not a farming incentive fund address.");
        rewardPoolDistributed = true;
        _mint(farmingIncentiveFund, FARMING_POOL_REWARD_ALLOCATION);
    }

    function _beforeTokenTransfer(address from, address to, uint256 amount) internal virtual override(ERC20) {
        super._beforeTokenTransfer(from, to, amount);
    }
}
