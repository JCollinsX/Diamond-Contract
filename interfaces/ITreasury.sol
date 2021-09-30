// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./IEpoch.sol";

interface ITreasury is IEpoch {
    function getEthPrice() external view returns (uint256);

    function buyBonds(uint256 amount, uint256 targetPrice) external;

    function redeemBonds(uint256 amount, uint256 targetPrice) external;
}
