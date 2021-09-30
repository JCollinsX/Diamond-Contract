// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/Context.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract Operator is Context, Ownable {
    address private _operator;

    event OperatorTransferred(address indexed previousOperator, address indexed newOperator);

    constructor() public {
        _operator = _msgSender();
        emit OperatorTransferred(address(0), _operator);
    }

    function operator() external view returns (address) {
        return _operator;
    }

    modifier onlyOperator() {
        require(_operator == msg.sender, "Operator: caller is not the operator.");
        _;
    }

    function isOperator() public view returns (bool) {
        return _msgSender() == _operator;
    }

    function transferOperator(address newOperator_) external onlyOwner {
        _transferOperator(newOperator_);
    }

    function _transferOperator(address newOperator_) internal {
        require(newOperator_ != address(0), "Operator: Zero address given for new operator.");
        emit OperatorTransferred(address(0), newOperator_);
        _operator = newOperator_;
    }
}

contract Destructor is Operator {
    function SelfDestruct(address payable addr) external onlyOperator {
        selfdestruct(addr);
    }
}
