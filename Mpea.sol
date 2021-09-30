// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";

import "./owner/Operator.sol";

contract Mpea is ERC20Burnable, Destructor {

    address public daoFund = 0x1C3dF661182c1f9cc8afE226915e5f91E93d1A6f;

    constructor() public ERC20("ChipShop Bond", "MPEAS") {
        _mint(daoFund, 0.1 ether); // Send 0.1 ether to deployer.
    }


    function mint(address recipient, uint256 amount) external onlyOperator returns (bool) {
        uint256 balanceBefore = balanceOf(recipient);
        _mint(recipient, amount);
        uint256 balanceAfter = balanceOf(recipient);
        return balanceAfter > balanceBefore;
    }

    function _beforeTokenTransfer(address from, address to, uint256 amount) internal virtual override(ERC20) {
        super._beforeTokenTransfer(from, to, amount);
    }
}
