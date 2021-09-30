// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";

import "./owner/Operator.sol";

contract Chip is ERC20Burnable, Destructor {

    using SafeMath for uint256;

    address public DAO = 0x1C3dF661182c1f9cc8afE226915e5f91E93d1A6f;

    uint256 public constant INITIAL_DISTRIBUTION = 50 ether;
    uint256 public constant DAO_FUND = 10 ether;
    bool public rewardPoolDistributed = false;


    constructor() public ERC20("ChipShop Token", "CHIPS") {
        _mint(DAO, DAO_FUND);                 // Mint 10 CHIPs to DAO.
    }


    function mint(address recipient, uint256 amount) external onlyOperator returns (bool) {
        uint256 balanceBefore = balanceOf(recipient);
        _mint(recipient, amount);
        uint256 balanceAfter = balanceOf(recipient);
        return balanceAfter > balanceBefore;
    }

    function distributeReward(address distributionPool) external onlyOperator {
        require(!rewardPoolDistributed, "Chip.distributeReward(): Can distribute only once.");
        require(distributionPool != address(0), "Chip.distributeReward(): Not a distribution pool address.");
        rewardPoolDistributed = true;
        _mint(distributionPool, INITIAL_DISTRIBUTION);
    }

    function _beforeTokenTransfer(address from, address to, uint256 amount) internal virtual override(ERC20) {
        super._beforeTokenTransfer(from, to, amount);
    }
}
