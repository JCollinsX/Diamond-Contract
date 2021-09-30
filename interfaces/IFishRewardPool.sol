// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IFishRewardPool {
    function set(uint256 _pid, uint256 _allocPoint) external;
}
