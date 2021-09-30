// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IEpoch {
    function epoch() external view returns (uint256);

    function nextEpochPoint() external view returns (uint256);

    function nextEpochLength() external view returns (uint256);
}
