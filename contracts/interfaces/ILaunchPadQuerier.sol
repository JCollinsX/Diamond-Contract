// SPDX-License-Identifier: MIT
// solhint-disable func-name-mixedcase
pragma solidity 0.8.23;

import { ILaunchPadCommon } from "./ILaunchPadCommon.sol";

interface ILaunchPadQuerier is ILaunchPadCommon {
    function LAUNCHPAD_PRODUCT_ID() external pure returns (bytes32);

    function getLaunchPadsPaginated(uint256 quantity, uint256 page) external view returns (address[] memory);

    function getLaunchPadsCount() external view returns (uint256);

    function getLaunchPadsByInvestorPaginated(address investor, uint256 quantity, uint256 page) external view returns (address[] memory);

    function getLaunchPadsByInvestorCount() external view returns (uint256);

    function getLaunchPadCountByOwner(address owner) external view returns (uint256);

    function getLaunchPadsByOwnerPaginated(address owner, uint256 quantity, uint256 page) external view returns (address[] memory);

    function getMaxTokenCreationDeadline() external view returns (uint256);

    function getSignerAddress() external view returns (address);

    function getHeadstartByTier(uint256 tier) external view returns (uint256);

    function getLaunchPadTokenInfo(address launchPadAddress) external view returns (CreateErc20Input memory createErc20Input);

    function getLaunchPadMaxDurationIncrement() external view returns (uint256);
}
