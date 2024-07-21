// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import { Pausable } from "@solidstate/contracts/security/pausable/Pausable.sol";
import { ReentrancyGuard } from "@solidstate/contracts/security/reentrancy_guard/ReentrancyGuard.sol";
import { IAccessControl } from "@solidstate/contracts/access/access_control/IAccessControl.sol";
import { AccessControlStorage } from "@solidstate/contracts/access/access_control/AccessControlStorage.sol";
import { AccessControlInternal } from "@solidstate/contracts/access/access_control/AccessControlInternal.sol";

import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { SafeMath } from "@openzeppelin/contracts/utils/math/SafeMath.sol";
import { ILaunchPadFactory } from "../interfaces/ILaunchPadFactory.sol";
import { ILaunchPadQuerier } from "../interfaces/ILaunchPadQuerier.sol";
import { ILaunchPadProject, ILaunchPadCommon } from "../interfaces/ILaunchPadProject.sol";
import { LibLaunchPadProjectStorage } from "../libraries/LibLaunchPadProjectStorage.sol";
import { LibLaunchPadConsts } from "../libraries/LibLaunchPadConsts.sol";
import { IPaymentModule } from "../interfaces/IPaymentModule.sol";
import { LibSwapTokens } from "../libraries/LibSwapTokens.sol";

contract LaunchPadProjectFacet is ILaunchPadProject, ReentrancyGuard, Pausable, AccessControlInternal {
    using SafeMath for uint256;
    using SafeERC20 for IERC20Metadata;

    function buyTokens(uint256 tokenAmount) external payable override whenNotPaused whenSaleInProgress(6) nonReentrant {
        LibLaunchPadProjectStorage.DiamondStorage storage ds = LibLaunchPadProjectStorage.diamondStorage();

        if (ds.purchasedInfoByUser[msg.sender].purchasedTokenAmount == 0) {
            ds.investors.push(msg.sender);
        }

        ds.purchasedInfoByUser[msg.sender].purchasedTokenAmount = ds.purchasedInfoByUser[msg.sender].purchasedTokenAmount.add(tokenAmount);
        ds.totalTokensSold = ds.totalTokensSold.add(tokenAmount);

        require(
            ds.purchasedInfoByUser[msg.sender].purchasedTokenAmount <= ds.launchPadInfo.maxInvestPerWallet,
            "LaunchPad:buyTokens: Max invest per wallet reached"
        );
        require(ds.totalTokensSold <= ds.launchPadInfo.fundTarget.hardCap, "LaunchPad:buyTokens: Hard cap reached");

        _buyTokens(tokenAmount);
    }

    function _buyTokens(uint256 tokenAmount) internal {
        LibLaunchPadProjectStorage.DiamondStorage storage ds = LibLaunchPadProjectStorage.diamondStorage();
        uint256 cost = (tokenAmount * ds.launchPadInfo.price) / (10 ** tokenDecimals());
        // LaunchPad expects payment to be in native
        if (ds.launchPadInfo.paymentTokenAddress == address(0)) {
            require(msg.value == cost, "LaunchPad:buyTokens: Not enough ETH");
            ds.purchasedInfoByUser[msg.sender].paidTokenAmount = ds.purchasedInfoByUser[msg.sender].paidTokenAmount.add(cost);
        } else {
            // User wants to buyTokens with native
            if (msg.value > 0) {
                uint256 oldEthBalance = address(this).balance;
                address router = IPaymentModule(ds.launchPadFactory).getRouterAddress();
                bool isV2 = IPaymentModule(ds.launchPadFactory).isV2Router();
                if (isV2) {
                    LibSwapTokens._swapEthForExactTokensV2(msg.value, ds.launchPadInfo.paymentTokenAddress, cost, router);
                } else {
                    LibSwapTokens._swapEthForExactTokensV3(
                        msg.value,
                        ds.launchPadInfo.paymentTokenAddress,
                        cost,
                        router,
                        IPaymentModule(ds.launchPadFactory).getV3PoolFeeForTokenWithNative(ds.launchPadInfo.paymentTokenAddress)
                    );
                }
                // Refund leftover ETH
                uint256 weiToBeRefunded = msg.value - (oldEthBalance - address(this).balance);
                (bool success, ) = payable(msg.sender).call{ value: weiToBeRefunded }("");
                require(success, "Failed to refund leftover ETH");
            } else {
                IERC20Metadata paymentToken = IERC20Metadata(ds.launchPadInfo.paymentTokenAddress);
                require(paymentToken.allowance(msg.sender, address(this)) >= cost, "LaunchPad:buyTokens: Not enough allowance");
                paymentToken.safeTransferFrom(msg.sender, address(this), cost);
            }

            ds.purchasedInfoByUser[msg.sender].paidTokenAmount = ds.purchasedInfoByUser[msg.sender].paidTokenAmount.add(cost);
        }

        // Emit event
        ILaunchPadFactory(ds.launchPadFactory).addInvestorToLaunchPad(msg.sender);
        emit LibLaunchPadProjectStorage.TokensPurchased(msg.sender, tokenAmount);
    }

    function checkSignature(address wallet, uint256 tier, uint256 nonce, uint256 deadline, bytes memory signature) public view override {
        LibLaunchPadProjectStorage.DiamondStorage storage ds = LibLaunchPadProjectStorage.diamondStorage();
        address signer = ILaunchPadQuerier(ds.launchPadFactory).getSignerAddress();
        bytes32 messageHash = _prefixed(keccak256(abi.encodePacked(wallet, tier, nonce, deadline)));
        address recoveredSigner = recoverSigner(messageHash, signature);
        require(signer == recoveredSigner, "LaunchPad:validSignature: Invalid signature");
    }

    function claimTokens() external override whenNotPaused whenSaleEnded nonReentrant {
        LibLaunchPadProjectStorage.DiamondStorage storage ds = LibLaunchPadProjectStorage.diamondStorage();

        require(ds.launchPadInfo.tokenAddress != address(0), "LaunchPad:claimTokens: Token address is 0 - token does not exist");

        uint256 claimableAmount = getTokensAvailableToBeClaimed(msg.sender);
        require(claimableAmount > 0, "LaunchPad:claimTokens: No tokens to claim");

        ds.totalTokensClaimed = ds.totalTokensClaimed.add(claimableAmount);
        ds.purchasedInfoByUser[msg.sender].claimedTokenAmount = ds.purchasedInfoByUser[msg.sender].claimedTokenAmount.add(claimableAmount);

        // Transfer tokens to buyer
        IERC20Metadata token = IERC20Metadata(ds.launchPadInfo.tokenAddress);
        require(token.balanceOf(address(this)) >= claimableAmount, "LaunchPad:claimTokens: Not enough tokens in contract");
        token.safeTransfer(msg.sender, claimableAmount);
    }

    function getFeeShare() public view override returns (uint256) {
        LibLaunchPadProjectStorage.DiamondStorage storage ds = LibLaunchPadProjectStorage.diamondStorage();
        uint256 totalRaised = getTotalRaised();
        return totalRaised.mul(ds.feePercentage).div(LibLaunchPadConsts.BASIS_POINTS);
    }

    function getNextNonce(address user) external view override returns (uint256) {
        LibLaunchPadProjectStorage.DiamondStorage storage ds = LibLaunchPadProjectStorage.diamondStorage();
        return ds.buyTokenNonces[user].length;
    }

    function getTotalRaised() public view override returns (uint256) {
        LibLaunchPadProjectStorage.DiamondStorage storage ds = LibLaunchPadProjectStorage.diamondStorage();
        return ds.totalTokensSold.mul(ds.launchPadInfo.price).div(10 ** tokenDecimals());
    }

    function getLaunchPadAddress() external view override returns (address) {
        LibLaunchPadProjectStorage.DiamondStorage storage ds = LibLaunchPadProjectStorage.diamondStorage();
        return ds.launchPadFactory;
    }

    function getLaunchPadInfo() external view override returns (ILaunchPadCommon.LaunchPadInfo memory) {
        LibLaunchPadProjectStorage.DiamondStorage storage ds = LibLaunchPadProjectStorage.diamondStorage();
        return ds.launchPadInfo;
    }

    function getProjectOwnerRole() external pure override returns (bytes32) {
        return LibLaunchPadProjectStorage.LAUNCHPAD_OWNER_ROLE;
    }

    function getReleaseSchedule() external view override returns (ILaunchPadCommon.ReleaseScheduleV2[] memory) {
        LibLaunchPadProjectStorage.DiamondStorage storage ds = LibLaunchPadProjectStorage.diamondStorage();
        return ds.releaseScheduleV2;
    }

    function getReleasedTokensPercentage() public view override returns (uint256 releasedPerc) {
        LibLaunchPadProjectStorage.DiamondStorage storage ds = LibLaunchPadProjectStorage.diamondStorage();
        uint256 releaseScheduleV2Length = ds.releaseScheduleV2.length;
        for (uint256 i = 0; i < releaseScheduleV2Length; i++) {
            if (ds.releaseScheduleV2[i].timestamp <= block.timestamp) {
                releasedPerc += ds.releaseScheduleV2[i].percent;
            } else if (i > 0 && ds.releaseScheduleV2[i].isVesting && ds.releaseScheduleV2[i - 1].timestamp <= block.timestamp) {
                releasedPerc +=
                    (ds.releaseScheduleV2[i].percent * (block.timestamp - ds.releaseScheduleV2[i - 1].timestamp)) /
                    (ds.releaseScheduleV2[i].timestamp - ds.releaseScheduleV2[i - 1].timestamp);
                break;
            }
        }
        return releasedPerc;
    }

    function getTokensAvailableToBeClaimed(address user) public view override returns (uint256) {
        LibLaunchPadProjectStorage.DiamondStorage storage ds = LibLaunchPadProjectStorage.diamondStorage();
        if (ds.launchPadInfo.tokenAddress == address(0)) return 0;
        uint256 originalTokenDecimals = tokenDecimals();
        uint256 actualTokenDecimals = IERC20Metadata(ds.launchPadInfo.tokenAddress).decimals();
        uint256 releasedPerc = getReleasedTokensPercentage();
        uint256 claimableAmount = ds.purchasedInfoByUser[user].purchasedTokenAmount;
        if (releasedPerc < LibLaunchPadConsts.BASIS_POINTS)
            claimableAmount = ds.purchasedInfoByUser[user].purchasedTokenAmount.mul(releasedPerc).div(LibLaunchPadConsts.BASIS_POINTS);
        else if (releasedPerc == 0) return 0;

        claimableAmount = claimableAmount.mul(10 ** actualTokenDecimals).div(10 ** originalTokenDecimals);
        return claimableAmount.sub(ds.purchasedInfoByUser[user].claimedTokenAmount);
    }

    function getTokenCreationDeadline() external view override returns (uint256) {
        LibLaunchPadProjectStorage.DiamondStorage storage ds = LibLaunchPadProjectStorage.diamondStorage();
        return ds.launchPadInfo.tokenCreationDeadline;
    }

    function getPurchasedInfoByUser(address user) external view override returns (PurchasedInfo memory) {
        LibLaunchPadProjectStorage.DiamondStorage storage ds = LibLaunchPadProjectStorage.diamondStorage();
        return ds.purchasedInfoByUser[user];
    }

    function getInvestorsLength() external view override returns (uint256) {
        LibLaunchPadProjectStorage.DiamondStorage storage ds = LibLaunchPadProjectStorage.diamondStorage();
        return ds.investors.length;
    }

    function getAllInvestors() external view override returns (address[] memory) {
        LibLaunchPadProjectStorage.DiamondStorage storage ds = LibLaunchPadProjectStorage.diamondStorage();
        return ds.investors;
    }

    function getInvestorAddressByIndex(uint256 index) external view override returns (address) {
        LibLaunchPadProjectStorage.DiamondStorage storage ds = LibLaunchPadProjectStorage.diamondStorage();
        return ds.investors[index];
    }

    function isSuperchargerEnabled() external view override returns (bool) {
        LibLaunchPadProjectStorage.DiamondStorage storage ds = LibLaunchPadProjectStorage.diamondStorage();
        return ds.isSuperchargerEnabled;
    }

    /// builds a prefixed hash to mimic the behavior of eth_sign.
    function _prefixed(bytes32 hash) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", hash));
    }

    function recoverSigner(bytes32 message, bytes memory signature) public pure returns (address) {
        require(signature.length == 65, "LaunchPad:recoverSigner: Signature length is invalid");
        bytes32 r;
        bytes32 s;
        uint8 v;

        assembly {
            r := mload(add(signature, 32))
            s := mload(add(signature, 64))
            v := byte(0, mload(add(signature, 96)))
        }
        return ecrecover(message, v, r, s);
    }

    function tokenDecimals() public view override returns (uint256) {
        LibLaunchPadProjectStorage.DiamondStorage storage ds = LibLaunchPadProjectStorage.diamondStorage();
        return ILaunchPadQuerier(ds.launchPadFactory).getLaunchPadTokenInfo(address(this)).decimals;
    }

    function totalTokensSold() external view override returns (uint256) {
        LibLaunchPadProjectStorage.DiamondStorage storage ds = LibLaunchPadProjectStorage.diamondStorage();
        return ds.totalTokensSold;
    }

    function totalTokensClaimed() external view override returns (uint256) {
        LibLaunchPadProjectStorage.DiamondStorage storage ds = LibLaunchPadProjectStorage.diamondStorage();
        return ds.totalTokensClaimed;
    }

    /** MODIFIER */

    modifier onlySupercharger() {
        LibLaunchPadProjectStorage.DiamondStorage storage ds = LibLaunchPadProjectStorage.diamondStorage();
        require(ds.isSuperchargerEnabled, "LaunchPad:onlySupercharger: Supercharger is not enabled");
        _;
    }

    modifier whenSaleInProgress(uint256 tier) {
        LibLaunchPadProjectStorage.DiamondStorage storage ds = LibLaunchPadProjectStorage.diamondStorage();
        require(tier > 0, "LaunchPad:whenSaleInProgress: Tier must be greater than 0");
        uint256 headstart = ILaunchPadQuerier(ds.launchPadFactory).getSuperChargerHeadstartByTier(tier);
        uint256 startTimestamp = ds.launchPadInfo.startTimestamp - headstart;
        require(
            block.timestamp >= startTimestamp && block.timestamp <= ds.launchPadInfo.startTimestamp.add(ds.launchPadInfo.duration),
            "Sale is outside of the duration"
        );
        _;
    }

    modifier whenSaleEnded() {
        LibLaunchPadProjectStorage.DiamondStorage storage ds = LibLaunchPadProjectStorage.diamondStorage();
        require(block.timestamp > ds.launchPadInfo.startTimestamp.add(ds.launchPadInfo.duration), "Sale is still ongoing");
        _;
    }
}
