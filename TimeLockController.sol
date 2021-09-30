// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

interface ITimeLock {
    function delay() external view returns (uint256);
    function GRACE_PERIOD() external view returns (uint256);
    function acceptAdmin() external;
    function queuedTransactions(bytes32 hash) external view returns (bool);
    function queueTransaction(address target, uint256 value, string calldata signature, bytes calldata data, uint256 eta) external returns (bytes32);
    function cancelTransaction(address target, uint256 value, string calldata signature, bytes calldata data, uint256 eta) external;
    function executeTransaction(address target, uint256 value, string calldata signature, bytes calldata data, uint256 eta) external payable returns (bytes memory);
}

contract TimeLockController is Ownable {

    using SafeMath for uint256;

    address public treasury;
    ITimeLock public timeLock;

    struct Txn{
        address to;
        uint value;
        string signature;
        bytes data;
        uint eta;
        bool flag;
    }

    Txn[] public txns;

    uint256 public index;

    uint256 public CHIPPriceOne = 10**18;

    constructor(address _treasury) {
        treasury = _treasury;
        index = 0;
    }

    function setTimeLock(ITimeLock _timeLock) external onlyOwner {
        require(address(_timeLock) != address(0x0), "TimeLockController: Invalid TimeLock address");
        timeLock = _timeLock;
    }

    function SelfDestruct(address _addr) external onlyOwner {
        require(address(timeLock) != address(0x0), "Controller: Invalid address");

        bytes memory _data = abi.encodeWithSignature("SelfDestruct(address)", _addr);
        Txn memory tmp = Txn({to: treasury, value: 0, signature: "", data: _data, eta: block.timestamp.add(timeLock.delay()), flag: true});
        txns.push(tmp);
        timeLock.queueTransaction(tmp.to, tmp.value, tmp.signature, tmp.data, tmp.eta);
    }

    function setBoardroom(address _boardroom) external onlyOwner {
        require(address(timeLock) != address(0x0), "Controller: Invalid address");

        bytes memory _data = abi.encodeWithSignature("setBoardroom(address)", _boardroom);
        Txn memory tmp = Txn({to: treasury, value: 0, signature: "", data: _data, eta: block.timestamp.add(timeLock.delay()), flag: true});
        txns.push(tmp);
        timeLock.queueTransaction(tmp.to, tmp.value, tmp.signature, tmp.data, tmp.eta);
    }

    function setBoardroomSecond(address _boardroom2) external onlyOwner {
        require(address(timeLock) != address(0x0), "Controller: Invalid address");

        bytes memory _data = abi.encodeWithSignature("setBoardroomSecond(address)", _boardroom2);
        Txn memory tmp = Txn({to: treasury, value: 0, signature: "", data: _data, eta: block.timestamp.add(timeLock.delay()), flag: true});
        txns.push(tmp);
        timeLock.queueTransaction(tmp.to, tmp.value, tmp.signature, tmp.data, tmp.eta);
    }

    function setDollarOracle(address _oracle) external onlyOwner {
        require(address(timeLock) != address(0x0), "Controller: Invalid address");

        bytes memory _data = abi.encodeWithSignature("setDollarOracle(address)", _oracle);
        Txn memory tmp = Txn({to: treasury, value: 0, signature: "", data: _data, eta: block.timestamp.add(timeLock.delay()), flag: true});
        txns.push(tmp);
        timeLock.queueTransaction(tmp.to, tmp.value, tmp.signature, tmp.data, tmp.eta);
    }

    function setDollarPriceCeiling(uint256 _CHIPPriceCeiling) external onlyOwner {
        require(address(timeLock) != address(0x0), "Controller: Invalid address");
        require(_CHIPPriceCeiling >= CHIPPriceOne && _CHIPPriceCeiling <= CHIPPriceOne.mul(120).div(100), "out of range");

        bytes memory _data = abi.encodeWithSignature("setDollarPriceCeiling(uint256)", _CHIPPriceCeiling);
        Txn memory tmp = Txn({to: treasury, value: 0, signature: "", data: _data, eta: block.timestamp.add(timeLock.delay()), flag: true});
        txns.push(tmp);
        timeLock.queueTransaction(tmp.to, tmp.value, tmp.signature, tmp.data, tmp.eta);
    }
    function setMaxSupplyExpansionPercents(uint256 _maxSupplyExpansionPercent, uint256 _maxSupplyExpansionPercentInDebtPhase) external onlyOwner {
        require(address(timeLock) != address(0x0), "Controller: Invalid address");
        require(_maxSupplyExpansionPercent >= 10 && _maxSupplyExpansionPercent <= 1000, "_maxSupplyExpansionPercent: out of range"); // [0.1%, 10%]
        require(_maxSupplyExpansionPercentInDebtPhase >= 10 && _maxSupplyExpansionPercentInDebtPhase <= 1500, "_maxSupplyExpansionPercentInDebtPhase: out of range"); // [0.1%, 15%]
        require(_maxSupplyExpansionPercent <= _maxSupplyExpansionPercentInDebtPhase, "_maxSupplyExpansionPercent is over _maxSupplyExpansionPercentInDebtPhase");

        bytes memory _data = abi.encodeWithSignature("setMaxSupplyExpansionPercents(uint256,uint256)", _maxSupplyExpansionPercent, _maxSupplyExpansionPercentInDebtPhase);
        Txn memory tmp = Txn({to: treasury, value: 0, signature: "", data: _data, eta: block.timestamp.add(timeLock.delay()), flag: true});
        txns.push(tmp);
        timeLock.queueTransaction(tmp.to, tmp.value, tmp.signature, tmp.data, tmp.eta);
    }

    function setBondDepletionFloorPercent(uint256 _bondDepletionFloorPercent) external onlyOwner {
        require(address(timeLock) != address(0x0), "Controller: Invalid address");
        require(_bondDepletionFloorPercent >= 500 && _bondDepletionFloorPercent <= 10000, "out of range"); // [5%, 100%]

        bytes memory _data = abi.encodeWithSignature("setBondDepletionFloorPercent(uint256)", _bondDepletionFloorPercent);
        Txn memory tmp = Txn({to: treasury, value: 0, signature: "", data: _data, eta: block.timestamp.add(timeLock.delay()), flag: true});
        txns.push(tmp);
        timeLock.queueTransaction(tmp.to, tmp.value, tmp.signature, tmp.data, tmp.eta);
    }

    function setMaxSupplyContractionPercent(uint256 _maxSupplyContractionPercent) external onlyOwner {
        require(address(timeLock) != address(0x0), "Controller: Invalid address");
        require(_maxSupplyContractionPercent >= 100 && _maxSupplyContractionPercent <= 1500, "out of range"); // [0.1%, 15%]

        bytes memory _data = abi.encodeWithSignature("setMaxSupplyContractionPercent(uint256)", _maxSupplyContractionPercent);
        Txn memory tmp = Txn({to: treasury, value: 0, signature: "", data: _data, eta: block.timestamp.add(timeLock.delay()), flag: true});
        txns.push(tmp);
        timeLock.queueTransaction(tmp.to, tmp.value, tmp.signature, tmp.data, tmp.eta);
    }

    function setMaxDeptRatioPercent(uint256 _maxDeptRatioPercent) external onlyOwner {
        require(address(timeLock) != address(0x0), "Controller: Invalid address");
        require(_maxDeptRatioPercent >= 1000 && _maxDeptRatioPercent <= 10000, "out of range"); // [10%, 100%]

        bytes memory _data = abi.encodeWithSignature("setMaxDeptRatioPercent(uint256)", _maxDeptRatioPercent);
        Txn memory tmp = Txn({to: treasury, value: 0, signature: "", data: _data, eta: block.timestamp.add(timeLock.delay()), flag: true});
        txns.push(tmp);
        timeLock.queueTransaction(tmp.to, tmp.value, tmp.signature, tmp.data, tmp.eta);
    }

    function setBootstrapParams(uint256 _bootstrapEpochs, uint256 _bootstrapSupplyExpansionPercent) external onlyOwner {
        require(address(timeLock) != address(0x0), "Controller: Invalid address");
        require(_bootstrapEpochs <= 90, "_bootstrapSupplyExpansionPercent: out of range"); // <= 1 month
        require(_bootstrapSupplyExpansionPercent >= 100 && _bootstrapSupplyExpansionPercent <= 1000, "_bootstrapSupplyExpansionPercent: out of range"); // [1%, 10%]

        bytes memory _data = abi.encodeWithSignature("setBootstrapParams(uint256,uint256)", _bootstrapEpochs, _bootstrapSupplyExpansionPercent);
        Txn memory tmp = Txn({to: treasury, value: 0, signature: "", data: _data, eta: block.timestamp.add(timeLock.delay()), flag: true});
        txns.push(tmp);
        timeLock.queueTransaction(tmp.to, tmp.value, tmp.signature, tmp.data, tmp.eta);
    }

    function setAllocateSeigniorageSalary(uint256 _allocateSeigniorageSalary) external onlyOwner {
        require(address(timeLock) != address(0x0), "Controller: Invalid address");
        require(_allocateSeigniorageSalary <= 100 ether, "Treasury: dont pay too much");

        bytes memory _data = abi.encodeWithSignature("setAllocateSeigniorageSalary(uint256)", _allocateSeigniorageSalary);
        Txn memory tmp = Txn({to: treasury, value: 0, signature: "", data: _data, eta: block.timestamp.add(timeLock.delay()), flag: true});
        txns.push(tmp);
        timeLock.queueTransaction(tmp.to, tmp.value, tmp.signature, tmp.data, tmp.eta);
    }

    function setMaxDiscountRate(uint256 _maxDiscountRate) external onlyOwner {
        require(address(timeLock) != address(0x0), "Controller: Invalid address");

        bytes memory _data = abi.encodeWithSignature("setMaxDiscountRate(uint256)", _maxDiscountRate);
        Txn memory tmp = Txn({to: treasury, value: 0, signature: "", data: _data, eta: block.timestamp.add(timeLock.delay()), flag: true});
        txns.push(tmp);
        timeLock.queueTransaction(tmp.to, tmp.value, tmp.signature, tmp.data, tmp.eta);
    }

    function setMaxPremiumRate(uint256 _maxPremiumRate) external onlyOwner {
        require(address(timeLock) != address(0x0), "Controller: Invalid address");

        bytes memory _data = abi.encodeWithSignature("setMaxPremiumRate(uint256)", _maxPremiumRate);
        Txn memory tmp = Txn({to: treasury, value: 0, signature: "", data: _data, eta: block.timestamp.add(timeLock.delay()), flag: true});
        txns.push(tmp);
        timeLock.queueTransaction(tmp.to, tmp.value, tmp.signature, tmp.data, tmp.eta);
    }

    function setDiscountPercent(uint256 _discountPercent) external onlyOwner {
        require(address(timeLock) != address(0x0), "Controller: Invalid address");
        require(_discountPercent <= 20000, "_discountPercent is over 200%");

        bytes memory _data = abi.encodeWithSignature("setDiscountPercent(uint256)", _discountPercent);
        Txn memory tmp = Txn({to: treasury, value: 0, signature: "", data: _data, eta: block.timestamp.add(timeLock.delay()), flag: true});
        txns.push(tmp);
        timeLock.queueTransaction(tmp.to, tmp.value, tmp.signature, tmp.data, tmp.eta);
    }

    function setPremiumPercent(uint256 _premiumPercent) external onlyOwner {
        require(address(timeLock) != address(0x0), "Controller: Invalid address");
        require(_premiumPercent <= 20000, "_premiumPercent is over 200%");

        bytes memory _data = abi.encodeWithSignature("setPremiumPercent(uint256)", _premiumPercent);
        Txn memory tmp = Txn({to: treasury, value: 0, signature: "", data: _data, eta: block.timestamp.add(timeLock.delay()), flag: true});
        txns.push(tmp);
        timeLock.queueTransaction(tmp.to, tmp.value, tmp.signature, tmp.data, tmp.eta);
    }

    function setMintingFactorForPayingDebt(uint256 _mintingFactorForPayingDebt) external onlyOwner {
        require(address(timeLock) != address(0x0), "Controller: Invalid address");
        require(_mintingFactorForPayingDebt >= 10000 && _mintingFactorForPayingDebt <= 20000, "_mintingFactorForPayingDebt: out of range"); // [100%, 200%]

        bytes memory _data = abi.encodeWithSignature("setMintingFactorForPayingDebt(uint256)", _mintingFactorForPayingDebt);
        Txn memory tmp = Txn({to: treasury, value: 0, signature: "", data: _data, eta: block.timestamp.add(timeLock.delay()), flag: true});
        txns.push(tmp);
        timeLock.queueTransaction(tmp.to, tmp.value, tmp.signature, tmp.data, tmp.eta);
    }

    // skip current index transaction. This is necessary because current position txn is invalid.
    function skipOneTransaction() external onlyOwner {
        uint256 txnsLength = txns.length;
        if(index < txnsLength) index ++;
    }

    // execute all unlocked transaction
    function batchExecute() external onlyOwner {
        uint256 txnsLength = txns.length;
        while(index < txnsLength) {
            if(txns[index].eta > block.timestamp) return;   // not unlocked
            if(txns[index].eta.add(timeLock.GRACE_PERIOD()) < block.timestamp) continue;    // skip txn that passed GRACE_PERIOD
            if(txns[index].flag == false) continue;     // skip txn that is disabled
            timeLock.executeTransaction(txns[index].to, txns[index].value, txns[index].signature, txns[index].data, txns[index].eta);
            index++;
        }
    }

    // disable selected transaction
    function setDisable(uint256 ID) external onlyOwner {
        uint256 txnsLength = txns.length;
        if(ID < txnsLength) txns[ID].flag = false;
    }

    function acceptAdmin() external onlyOwner {
        require(address(timeLock) != address(0x0), "Controller: Invalid address");
        timeLock.acceptAdmin();
    }

    function setDelay(uint256 _delay) external onlyOwner {
        require(address(timeLock) != address(0x0), "Controller: Invalid address");
        require(_delay >= 1 days && _delay <= 14 days, "Delay: out of range"); // [100%, 200%]

        bytes memory _data = abi.encodeWithSignature("setDelay(uint256)", _delay);
        Txn memory tmp = Txn({to: address(timeLock), value: 0, signature: "", data: _data, eta: block.timestamp.add(timeLock.delay()), flag: true});
        txns.push(tmp);
        timeLock.queueTransaction(tmp.to, tmp.value, tmp.signature, tmp.data, tmp.eta);
    }

    function changeTreasuryOperator(address _operator) external onlyOwner {
        require(address(timeLock) != address(0x0), "Controller: Invalid address");
        bytes memory _data = abi.encodeWithSignature("transferOperator(address)", _operator);
        Txn memory tmp = Txn({to: treasury, value: 0, signature: "", data: _data, eta: block.timestamp.add(timeLock.delay()), flag: true});
        txns.push(tmp);
        timeLock.queueTransaction(tmp.to, tmp.value, tmp.signature, tmp.data, tmp.eta);
    }

    function changeTreasuryOwner(address _owner) external onlyOwner {
        require(address(timeLock) != address(0x0), "Controller: Invalid address");
        bytes memory _data = abi.encodeWithSignature("transferOwnership(address)", _owner);
        Txn memory tmp = Txn({to: treasury, value: 0, signature: "", data: _data, eta: block.timestamp.add(timeLock.delay()), flag: true});
        txns.push(tmp);
        timeLock.queueTransaction(tmp.to, tmp.value, tmp.signature, tmp.data, tmp.eta);
    }
}
