// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import { ILaunchPadCommon } from "../interfaces/ILaunchPadProject.sol";
import { ILaunchPadProject } from "../interfaces/ILaunchPadProject.sol";

/// @notice storage for LaunchPads created by users

library LibLaunchPadProjectStorage {
    bytes32 internal constant DIAMOND_STORAGE_POSITION = keccak256("launchpad.project.storage");
    bytes32 internal constant LAUNCHPAD_OWNER_ROLE = keccak256("LAUNCHPAD_OWNER_ROLE");
    bytes32 internal constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    struct DiamondStorage {
        ILaunchPadCommon.LaunchPadInfo launchPadInfo;
        address launchPadFactory;
        uint256 totalTokensSold;
        uint256 totalTokensClaimed;
        uint256 feePercentage; // in basis points 1e4
        bool feeShareCollected;
        bool isSuperchargerEnabled;
        ILaunchPadCommon.ReleaseSchedule[] releaseSchedule;
        ILaunchPadCommon.ReleaseScheduleV2[] releaseScheduleV2;
        mapping(address => ILaunchPadProject.PurchasedInfo) purchasedInfoByUser;
        address[] investors;
        mapping(address => uint256[]) buyTokenNonces;
        mapping(uint256 => mapping(uint256 => bool)) signatureUsedByIndexByChainId;
    }

    event TokensPurchased(address indexed buyer, uint256 amount);

    function diamondStorage() internal pure returns (DiamondStorage storage ds) {
        bytes32 position = DIAMOND_STORAGE_POSITION;
        // solhint-disable-next-line no-inline-assembly
        assembly {
            ds.slot := position
        }
    }
}
