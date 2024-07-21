// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

library LibLaunchPadConsts {
    bytes32 internal constant PRODUCT_ID = keccak256("launchpad");
    uint256 internal constant BURN_BASIS_POINTS = 5_000;
    uint256 internal constant BASIS_POINTS = 10_000;
    address internal constant BURN_ADDRESS = 0x000000000000000000000000000000000000dEaD;
}
