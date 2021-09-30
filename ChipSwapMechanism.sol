// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";

import "./owner/Operator.sol";

// Note: The owner of this contract will be the Treasury contract.

contract ChipSwapMechanism is Destructor {

    using SafeMath for uint256;

    ERC20Burnable public CHIPS;
    ERC20Burnable public FISH;

    uint256 public availableFish = 0;
    uint256 public lockedFish = 50 ether;
    uint256 public hourlyAllocatedFish = lockedFish.div(365).div(24);


    event SwapExecuted(address indexed Address, uint256 chipAmount, uint256 fishAmount);


    constructor(address _chips, address _fish) public {
        CHIPS = ERC20Burnable(_chips);
        FISH = ERC20Burnable(_fish);
    }


    modifier isSwappable() {
        require(CHIPS.totalSupply() >= 60 ether, "ChipSwapMechanism.isSwappable(): Insufficient supply.");
        _;
    }


    function swap(address account, uint256 _chipAmount, uint256 _fishAmount) external isSwappable onlyOperator {
        require(getFishBalance() >= _fishAmount, "ChipSwapMechanism.swap(): Insufficient FISH balance.");
        require(getChipBalance(account) >= _chipAmount, "ChipSwapMechanism.swap(): Insufficient CHIP balance.");
        require(availableFish >= _fishAmount, "ChipSwapMechanism.swap(): Insufficient FISH population.");
        require(account != address(0x0), "ChipSwapMechanism.swap(): Invalid address.");
        availableFish = availableFish.sub(_fishAmount);
        FISH.transfer(account, _fishAmount);
        emit SwapExecuted(account, _chipAmount, _fishAmount);
    }

    function withdrawFish(uint256 _amount) private onlyOperator {
        require(getFishBalance() >= _amount, "ChipSwapMechanism.withdrawFish(): Insufficient FISH balance.");
        FISH.transfer(msg.sender, _amount);
    }

    function getFishBalance() public view returns (uint256) {
        return FISH.balanceOf(address(this));
    }

    function getChipBalance(address user) public view returns (uint256) {
        return CHIPS.balanceOf(user);
    }

    function unlockFish(uint _hours) external onlyOperator {
        uint256 unlockFishAmount = hourlyAllocatedFish.mul(_hours);
        if(unlockFishAmount > lockedFish) unlockFishAmount = lockedFish;
        lockedFish = lockedFish.sub(unlockFishAmount);
        availableFish = availableFish.add(unlockFishAmount);
    }
}
