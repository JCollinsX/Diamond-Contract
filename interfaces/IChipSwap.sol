// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IChipSwap {
    function unlockFish(uint256 _hours) external;

    function swap(
        address user,
        uint256 _chipAmount,
        uint256 _fishAmount
    ) external;
}
