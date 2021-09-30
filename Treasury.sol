// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";

import "./owner/Operator.sol";
import "./utils/ContractGuard.sol";
import "./interfaces/IEpoch.sol";
import "./interfaces/IOracle.sol";
import "./interfaces/ITreasury.sol";
import "./interfaces/IChipSwap.sol";
import "./interfaces/IBoardroom.sol";
import "./interfaces/IBasisAsset.sol";
import "./interfaces/IFishRewardPool.sol";

contract Treasury is ContractGuard, ITreasury, Destructor {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;

    // State variables.

    bool public migrated = false;
    bool public initialized = false;

    // Epoch.

    struct epochHistory {
        uint256 epochID;
        uint256 bonded;
        uint256 redeemed;
        uint256 expanded_amount;
    }

    epochHistory[] public history;

    uint256 public startTime;
    uint256 public lastEpochTime;
    uint256 private _epoch = 0;
    uint256 public epochSupplyContractionLeft = 0;

    // Core components.

    address public CHIP;
    address public FISH;
    address public MPEA;

    address public boardroom;
    address public boardroomSecond;
    address public CHIPOracle;

    address public BNB;
    address public CHIP_BNB;
    address public FISH_BNB;

    IChipSwap public ChipSwapMechanism;
    IFishRewardPool public fishPool_v2;

    // Price.

    uint256 public CHIPPriceOne;
    uint256 public CHIPPriceCeiling;
    uint256 public seigniorageSaved;
    uint256 public maxSupplyExpansionPercent;
    uint256 public maxSupplyExpansionPercentInDebtPhase;
    uint256 public bondDepletionFloorPercent;
    uint256 public seigniorageExpansionFloorPercent;
    uint256 public maxSupplyContractionPercent;
    uint256 public maxDeptRatioPercent;
    uint256 public bootstrapEpochs;
    uint256 public bootstrapSupplyExpansionPercent;
    uint256 public previousEpochDollarPrice;
    uint256 public allocateSeigniorageSalary;
    uint256 public maxDiscountRate; // When purchasing MPEA.
    uint256 public maxPremiumRate; // When redeeming MPEA.
    uint256 public discountPercent;
    uint256 public premiumPercent;
    uint256 public mintingFactorForPayingDebt; // Print extra CHIP during dept phase.
    address public daoFund;
    uint256 public daoFundSharedPercent;
    address public secondBoardRoomFund;
    uint256 public secondBoardRoomFundSharedPercent;
    address public marketingFund;
    uint256 public marketingFundSharedPercent;

    // Events.

    event Initialized(address indexed executor, uint256 at);
    event Migration(address indexed target);
    event RedeemedBonds(address indexed from, uint256 CHIPAmount, uint256 bondAmount);
    event BoughtBonds(address indexed from, uint256 CHIPAmount, uint256 bondAmount);
    event TreasuryFunded(uint256 timestamp, uint256 seigniorage);
    event BoardroomFunded(uint256 timestamp, uint256 seigniorage);
    event DaoFundFunded(uint256 timestamp, uint256 seigniorage);
    event SecondBoardRoomFundFunded(uint256 timestamp, uint256 seigniorage);
    event MarketingFundFunded(uint256 timestamp, uint256 seigniorage);

    modifier checkCondition {
        require(!migrated, "Treasury: Migrated.");
        require(block.timestamp >= startTime, "Treasury: Not started yet.");
        _;
    }

    modifier checkEpoch {
        uint256 _nextEpochPoint = nextEpochPoint();
        require(block.timestamp >= _nextEpochPoint, "Treasury: Not opened yet.");
        _;
        lastEpochTime = _nextEpochPoint;
        _epoch = _epoch.add(1);
        epochSupplyContractionLeft = (getEthPrice() > CHIPPriceCeiling) ? 0 : IERC20(CHIP).totalSupply().mul(maxSupplyContractionPercent).div(10000);
    }

    modifier checkOperator {
        require(IBasisAsset(CHIP).operator() == address(this) && IBasisAsset(MPEA).operator() == address(this) && Operator(boardroom).operator() == address(this), "Treasury: Bad permissions.");
        _;
    }

    modifier notInitialized {
        require(!initialized, "Treasury: Already initialized.");
        _;
    }

    // State.

    function isMigrated() external view returns (bool) {
        return migrated;
    }

    function isInitialized() external view returns (bool) {
        return initialized;
    }

    // Epoch.

    function epoch() external view override returns (uint256) {
        return _epoch;
    }

    function nextEpochPoint() public view override returns (uint256) {
        return lastEpochTime.add(nextEpochLength());
    }

    function nextEpochLength() public view override returns (uint256 _length) {
        if (_epoch <= bootstrapEpochs) {
            // 3 first epochs with 6h long.
            _length = 6 hours;
        } else {
            uint256 CHIPPrice = getEthPrice();
            _length = (CHIPPrice > CHIPPriceCeiling) ? 6 hours : 4 hours;
        }
    }

    // Oracle.
    function getEthPrice() public view override returns (uint256 CHIPPrice) {
        try IOracle(CHIPOracle).consult(CHIP, 1e18) returns (uint144 price) {
            return uint256(price);
        } catch {
            revert("Treasury: Failed to consult CHIP price from the oracle.");
        }
    }

    function getEthUpdatedPrice() public view returns (uint256 _CHIPPrice) {
        try IOracle(CHIPOracle).twap(CHIP, 1e18) returns (uint144 price) {
            return uint256(price);
        } catch {
            revert("Treasury: failed to consult CHIP price from the oracle");
        }
    }

    // Budget.

    function getReserve() external view returns (uint256) {
        return seigniorageSaved;
    }

    function getBurnableDollarLeft() external view returns (uint256 _burnableDollarLeft) {
        uint256 _CHIPPrice = getEthPrice();
        if (_CHIPPrice <= CHIPPriceOne) {
            uint256 _CHIPSupply = IERC20(CHIP).totalSupply();
            uint256 _bondMaxSupply = _CHIPSupply.mul(maxDeptRatioPercent).div(10000);
            uint256 _bondSupply = IERC20(MPEA).totalSupply();
            if (_bondMaxSupply > _bondSupply) {
                uint256 _maxMintableBond = _bondMaxSupply.sub(_bondSupply);
                uint256 _maxBurnableDollar = _maxMintableBond.mul(_CHIPPrice).div(1e18);
                _burnableDollarLeft = Math.min(epochSupplyContractionLeft, _maxBurnableDollar);
            }
        }
    }

    function getRedeemableBonds() external view returns (uint256 _redeemableBonds) {
        uint256 _CHIPPrice = getEthPrice();
        if (_CHIPPrice > CHIPPriceCeiling) {
            uint256 _totalDollar = IERC20(CHIP).balanceOf(address(this));
            uint256 _rate = getBondPremiumRate();
            if (_rate > 0) {
                _redeemableBonds = _totalDollar.mul(1e18).div(_rate);
            }
        }
    }

    function getBondDiscountRate() public view returns (uint256 _rate) {
        uint256 _CHIPPrice = getEthPrice();
        if (_CHIPPrice <= CHIPPriceOne) {
            if (discountPercent == 0) {
                // No discount.
                _rate = CHIPPriceOne;
            } else {
                uint256 _bondAmount = CHIPPriceOne.mul(1e18).div(_CHIPPrice); // To burn 1 CHIP.
                uint256 _discountAmount = _bondAmount.sub(CHIPPriceOne).mul(discountPercent).div(10000);
                _rate = CHIPPriceOne.add(_discountAmount);
                if (maxDiscountRate > 0 && _rate > maxDiscountRate) {
                    _rate = maxDiscountRate;
                }
            }
        }
    }

    function getBondPremiumRate() public view returns (uint256 _rate) {
        uint256 _CHIPPrice = getEthPrice();
        if (_CHIPPrice > CHIPPriceCeiling) {
            if (premiumPercent == 0) {
                // No premium bonus.
                _rate = CHIPPriceOne;
            } else {
                uint256 _premiumAmount = _CHIPPrice.sub(CHIPPriceOne).mul(premiumPercent).div(10000);
                _rate = CHIPPriceOne.add(_premiumAmount);
                if (maxDiscountRate > 0 && _rate > maxDiscountRate) {
                    _rate = maxDiscountRate;
                }
            }
        }
    }

    // Governance.

    function initialize(
        address _CHIP,
        address _MPEA,
        address _FISH,
        uint256 _startTime
    ) external onlyOperator notInitialized {
        CHIP = _CHIP;
        MPEA = _MPEA;
        FISH = _FISH;
        startTime = _startTime;
        lastEpochTime = _startTime.sub(6 hours);
        CHIPPriceOne = 10**18;
        CHIPPriceCeiling = CHIPPriceOne.mul(10001).div(10000);
        maxSupplyExpansionPercent = 300; // Up to 3.0% supply for expansion.
        maxSupplyExpansionPercentInDebtPhase = 300; // Up to 3% supply for expansion in debt phase (to pay debt faster).
        bondDepletionFloorPercent = 10000; // 100% of Bond supply for depletion floor.
        seigniorageExpansionFloorPercent = 5000; // At least 50% of expansion reserved for boardroom.
        maxSupplyContractionPercent = 350; // Up to 3.5% supply for contraction (to burn CHIP and mint MPEA).
        maxDeptRatioPercent = 5000; // Up to 50% supply of MEB to purchase.
        bootstrapEpochs = 3; // First 3 epochs with expansion.
        bootstrapSupplyExpansionPercent = 300;
        seigniorageSaved = IERC20(CHIP).balanceOf(address(this)); // Set seigniorageSaved to its balance.
        allocateSeigniorageSalary = 0.001 ether; // 0.001 CHIP salary for calling allocateSeigniorage.
        maxDiscountRate = 13e17; // 30% - when purchasing bond.
        maxPremiumRate = 13e17; // 30% - when redeeming bond.
        discountPercent = 0; // No discount.
        premiumPercent = 6500; // 65% premium.
        mintingFactorForPayingDebt = 10000; // 100%
        daoFundSharedPercent = 3500; // 35% toward DAO Fund.
        secondBoardRoomFundSharedPercent = 0;
        marketingFundSharedPercent = 0;
        initialized = true;
        emit Initialized(msg.sender, block.number);
    }

    function resetStartTime(uint256 _startTime) external onlyOperator {
        require(_epoch == 0, "already started");
        startTime = _startTime;
        lastEpochTime = _startTime.sub(6 hours);
    }

    function setBoardroom(address _boardroom) external onlyOperator {
        boardroom = _boardroom;
    }

    function setBoardroomSecond(address _boardroom2) external onlyOperator {
        boardroomSecond = _boardroom2;
    }

    function setDollarOracle(address _CHIPOracle) external onlyOperator {
        CHIPOracle = _CHIPOracle;
    }

    function setDollarPriceCeiling(uint256 _CHIPPriceCeiling) external onlyOperator {
        require(_CHIPPriceCeiling >= CHIPPriceOne && _CHIPPriceCeiling <= CHIPPriceOne.mul(120).div(100), "out of range"); // [$1.0, $1.2]
        CHIPPriceCeiling = _CHIPPriceCeiling;
    }

    function setMaxSupplyExpansionPercents(uint256 _maxSupplyExpansionPercent, uint256 _maxSupplyExpansionPercentInDebtPhase) external onlyOperator {
        require(_maxSupplyExpansionPercent >= 10 && _maxSupplyExpansionPercent <= 1000, "_maxSupplyExpansionPercent: out of range"); // [0.1%, 10%]
        require(_maxSupplyExpansionPercentInDebtPhase >= 10 && _maxSupplyExpansionPercentInDebtPhase <= 1500, "_maxSupplyExpansionPercentInDebtPhase: out of range"); // [0.1%, 15%]
        require(_maxSupplyExpansionPercent <= _maxSupplyExpansionPercentInDebtPhase, "_maxSupplyExpansionPercent is over _maxSupplyExpansionPercentInDebtPhase");
        maxSupplyExpansionPercent = _maxSupplyExpansionPercent;
        maxSupplyExpansionPercentInDebtPhase = _maxSupplyExpansionPercentInDebtPhase;
    }

    function setBondDepletionFloorPercent(uint256 _bondDepletionFloorPercent) external onlyOperator {
        require(_bondDepletionFloorPercent >= 500 && _bondDepletionFloorPercent <= 10000, "out of range"); // [5%, 100%]
        bondDepletionFloorPercent = _bondDepletionFloorPercent;
    }

    function setMaxSupplyContractionPercent(uint256 _maxSupplyContractionPercent) external onlyOperator {
        require(_maxSupplyContractionPercent >= 100 && _maxSupplyContractionPercent <= 1500, "out of range"); // [0.1%, 15%]
        maxSupplyContractionPercent = _maxSupplyContractionPercent;
    }

    function setMaxDeptRatioPercent(uint256 _maxDeptRatioPercent) external onlyOperator {
        require(_maxDeptRatioPercent >= 1000 && _maxDeptRatioPercent <= 10000, "out of range"); // [10%, 100%]
        maxDeptRatioPercent = _maxDeptRatioPercent;
    }

    function setBootstrapParams(uint256 _bootstrapEpochs, uint256 _bootstrapSupplyExpansionPercent) external onlyOperator {
        require(_bootstrapEpochs <= 90, "_bootstrapSupplyExpansionPercent: out of range"); // <= 1 month
        require(_bootstrapSupplyExpansionPercent >= 100 && _bootstrapSupplyExpansionPercent <= 1000, "_bootstrapSupplyExpansionPercent: out of range"); // [1%, 10%]
        bootstrapEpochs = _bootstrapEpochs;
        bootstrapSupplyExpansionPercent = _bootstrapSupplyExpansionPercent;
    }

    function setExtraFunds(
        address _daoFund,
        uint256 _daoFundSharedPercent,
        address _secondBoardRoomFund,
        uint256 _secondBoardRoomFundSharedPercent,
        address _marketingFund,
        uint256 _marketingFundSharedPercent
    ) external onlyOperator {
        require(_daoFund != address(0), "zero");
        require(_daoFundSharedPercent <= 3500, "out of range"); // <= 35%
        require(_secondBoardRoomFund != address(0), "zero");
        require(_secondBoardRoomFundSharedPercent <= 1000, "out of range"); // <= 10%
        require(_marketingFund != address(0), "zero");
        require(_marketingFundSharedPercent <= 1000, "out of range"); // <= 10%
        daoFund = _daoFund;
        daoFundSharedPercent = _daoFundSharedPercent;
        secondBoardRoomFund = _secondBoardRoomFund;
        secondBoardRoomFundSharedPercent = _secondBoardRoomFundSharedPercent;
        marketingFund = _marketingFund;
        marketingFundSharedPercent = _marketingFundSharedPercent;
    }

    function setAllocateSeigniorageSalary(uint256 _allocateSeigniorageSalary) external onlyOperator {
        require(_allocateSeigniorageSalary <= 100 ether, "Treasury: dont pay too much");
        allocateSeigniorageSalary = _allocateSeigniorageSalary;
    }

    function setMaxDiscountRate(uint256 _maxDiscountRate) external onlyOperator {
        maxDiscountRate = _maxDiscountRate;
    }

    function setMaxPremiumRate(uint256 _maxPremiumRate) external onlyOperator {
        maxPremiumRate = _maxPremiumRate;
    }

    function setDiscountPercent(uint256 _discountPercent) external onlyOperator {
        require(_discountPercent <= 20000, "_discountPercent is over 200%");
        discountPercent = _discountPercent;
    }

    function setPremiumPercent(uint256 _premiumPercent) external onlyOperator {
        require(_premiumPercent <= 20000, "_premiumPercent is over 200%");
        premiumPercent = _premiumPercent;
    }

    function setMintingFactorForPayingDebt(uint256 _mintingFactorForPayingDebt) external onlyOperator {
        require(_mintingFactorForPayingDebt >= 10000 && _mintingFactorForPayingDebt <= 20000, "_mintingFactorForPayingDebt: out of range"); // [100%, 200%]
        mintingFactorForPayingDebt = _mintingFactorForPayingDebt;
    }

    function migrate(address target) external onlyOperator checkOperator {
        require(!migrated, "Treasury: migrated");

        // CHIP
        Operator(CHIP).transferOperator(target);
        Operator(CHIP).transferOwnership(target);
        IERC20(CHIP).transfer(target, IERC20(CHIP).balanceOf(address(this)));

        // MPEA
        Operator(MPEA).transferOperator(target);
        Operator(MPEA).transferOwnership(target);
        IERC20(MPEA).transfer(target, IERC20(MPEA).balanceOf(address(this)));

        // FISH
        Operator(FISH).transferOperator(target);
        Operator(FISH).transferOwnership(target);
        IERC20(FISH).transfer(target, IERC20(FISH).balanceOf(address(this)));

        migrated = true;
        emit Migration(target);
    }

    // Mutators.

    function _updateEthPrice() internal {
        try IOracle(CHIPOracle).update() {} catch {}
    }

    function buyBonds(uint256 _CHIPAmount, uint256 targetPrice) external override onlyOneBlock checkCondition checkOperator {
        require(_epoch >= bootstrapEpochs, "Treasury: still in boostrap");
        require(_CHIPAmount > 0, "Treasury: cannot purchase bonds with zero amount");
        uint256 CHIPPrice = getEthPrice();

        require(
            CHIPPrice < CHIPPriceOne, // price < 1 ETH.
            "Treasury: CHIP Price not eligible for bond purchase."
        );
        require(_CHIPAmount <= epochSupplyContractionLeft, "Treasury: Not enough bond left to purchase.");
        uint256 _rate = getBondDiscountRate();
        require(_rate > 0, "Treasury: Invalid bond rate.");
        uint256 _bondAmount = _CHIPAmount.mul(_rate).div(1e18);
        uint256 CHIPSupply = IERC20(CHIP).totalSupply();
        uint256 newBondSupply = IERC20(MPEA).totalSupply().add(_bondAmount);
        require(newBondSupply <= CHIPSupply.mul(maxDeptRatioPercent).div(10000), "Over max debt ratio.");
        IBasisAsset(CHIP).burnFrom(msg.sender, _CHIPAmount);
        IBasisAsset(MPEA).mint(msg.sender, _bondAmount);
        epochSupplyContractionLeft = epochSupplyContractionLeft.sub(_CHIPAmount);
        _updateEthPrice();
        history[_epoch - 1].bonded = history[_epoch - 1].bonded.add(_bondAmount);
        emit BoughtBonds(msg.sender, _CHIPAmount, _bondAmount);
    }

    function redeemBonds(uint256 _bondAmount, uint256 targetPrice) external override onlyOneBlock checkCondition checkOperator {
        require(_bondAmount > 0, "Treasury: Cannot redeem bonds with zero amount.");
        uint256 CHIPPrice = getEthPrice();
        require(
            CHIPPrice > CHIPPriceCeiling, // price > $1.01.
            "Treasury: CHIP Price not eligible for bond purchase."
        );
        uint256 _rate = getBondPremiumRate();
        require(_rate > 0, "Treasury: invalid bond rate");
        uint256 _CHIPAmount = _bondAmount.mul(_rate).div(1e18);
        require(IERC20(CHIP).balanceOf(address(this)) >= _CHIPAmount, "Treasury: Treasury has no more budget.");
        seigniorageSaved = seigniorageSaved.sub(Math.min(seigniorageSaved, _CHIPAmount));
        IBasisAsset(MPEA).burnFrom(msg.sender, _bondAmount);
        IERC20(CHIP).safeTransfer(msg.sender, _CHIPAmount);
        history[_epoch - 1].redeemed = history[_epoch - 1].redeemed.add(_CHIPAmount);
        _updateEthPrice();
        emit RedeemedBonds(msg.sender, _CHIPAmount, _bondAmount);
    }

    function _sendToBoardRoom(uint256 _amount) internal {
        IBasisAsset(CHIP).mint(address(this), _amount);
        if (daoFundSharedPercent > 0) {
            uint256 _daoFundSharedAmount = _amount.mul(daoFundSharedPercent).div(10000);
            IERC20(CHIP).transfer(daoFund, _daoFundSharedAmount);
            emit DaoFundFunded(block.timestamp, _daoFundSharedAmount);
            _amount = _amount.sub(_daoFundSharedAmount);
        }
        if (marketingFundSharedPercent > 0) {
            uint256 _marketingSharedAmount = _amount.mul(marketingFundSharedPercent).div(10000);
            IERC20(CHIP).transfer(marketingFund, _marketingSharedAmount);
            emit MarketingFundFunded(block.timestamp, _marketingSharedAmount);
            _amount = _amount.sub(_marketingSharedAmount);
        }
        if (boardroomSecond != address(0) && secondBoardRoomFundSharedPercent > 0) {
            uint256 _secondBoardRoomFundSharedAmount = _amount.mul(secondBoardRoomFundSharedPercent).div(10000);
            IERC20(CHIP).safeApprove(boardroom, 0);
            IERC20(CHIP).safeApprove(boardroom, _secondBoardRoomFundSharedAmount);
            IBoardroom(boardroomSecond).allocateSeigniorage(_secondBoardRoomFundSharedAmount);
            _amount = _amount.sub(_secondBoardRoomFundSharedAmount);
        }
        IERC20(CHIP).safeApprove(boardroom, 0);
        IERC20(CHIP).safeApprove(boardroom, _amount);
        IBoardroom(boardroom).allocateSeigniorage(_amount);
        emit BoardroomFunded(block.timestamp, _amount);
    }

    function allocateSeigniorage() external onlyOneBlock checkCondition checkEpoch checkOperator {
        history.push(epochHistory({epochID: _epoch, bonded: 0, redeemed: 0, expanded_amount: 0}));
        _updateEthPrice();
        previousEpochDollarPrice = getEthPrice();
        uint256 CHIPSupply = IERC20(CHIP).totalSupply().sub(seigniorageSaved);
        uint256 ExpansionPercent;
        if(CHIPSupply < 500 ether) ExpansionPercent = 300;                                      // 3%
        else if(CHIPSupply >= 500 ether && CHIPSupply < 1000 ether) ExpansionPercent = 200;     // 2%
        else if(CHIPSupply >= 1000 ether && CHIPSupply < 2000 ether) ExpansionPercent = 150;    // 1.5%
        else if(CHIPSupply >= 2000 ether && CHIPSupply < 5000 ether) ExpansionPercent = 125;    // 1.25%
        else if(CHIPSupply >= 5000 ether && CHIPSupply < 10000 ether) ExpansionPercent = 100;   // 1%
        else if(CHIPSupply >= 10000 ether && CHIPSupply < 20000 ether) ExpansionPercent = 75;   // 0.75%
        else if(CHIPSupply >= 20000 ether && CHIPSupply < 50000 ether) ExpansionPercent = 50;   // 0.5%
        else if(CHIPSupply >= 50000 ether && CHIPSupply < 100000 ether) ExpansionPercent = 25;  // 0.25%
        else if(CHIPSupply >= 100000 ether && CHIPSupply < 200000 ether) ExpansionPercent = 15; // 0.15%
        else ExpansionPercent = 10;                                                             // 0.1%
        maxSupplyExpansionPercent = ExpansionPercent;
        if (_epoch < bootstrapEpochs) {
            // 3 first epochs expansion.
            _sendToBoardRoom(CHIPSupply.mul(ExpansionPercent).div(10000));
            ChipSwapMechanism.unlockFish(6); // When expansion phase, 6 hours worth fish will be unlocked.
            fishPool_v2.set(4, 0);           // Disable MPEA/CHIP pool when expansion phase.
            history[_epoch].expanded_amount = CHIPSupply.mul(ExpansionPercent).div(10000);
        } else {
            if (previousEpochDollarPrice > CHIPPriceCeiling) {
                // Expansion ($CHIP Price > 1 ETH): there is some seigniorage to be allocated
                fishPool_v2.set(4, 0); // Disable MPEA/CHIP pool when expansion phase.
                ChipSwapMechanism.unlockFish(6); // When expansion phase, 6 hours worth fish will be unlocked.
                uint256 bondSupply = IERC20(MPEA).totalSupply();
                uint256 _percentage = previousEpochDollarPrice.sub(CHIPPriceOne);
                uint256 _savedForBond;
                uint256 _savedForBoardRoom;
                if (seigniorageSaved >= bondSupply.mul(bondDepletionFloorPercent).div(10000)) {
                    // Saved enough to pay dept, mint as usual rate.
                    uint256 _mse = ExpansionPercent.mul(1e14);
                    if (_percentage > _mse) {
                        _percentage = _mse;
                    }
                    _savedForBoardRoom = CHIPSupply.mul(_percentage).div(1e18);
                    history[_epoch].expanded_amount = CHIPSupply.mul(_percentage).div(1e18);
                } else {
                    // Have not saved enough to pay dept, mint more.
                    uint256 _mse = ExpansionPercent.mul(1e14);
                    if (_percentage > _mse) {
                        _percentage = _mse;
                    }
                    uint256 _seigniorage = CHIPSupply.mul(_percentage).div(1e18);
                    history[_epoch].expanded_amount = CHIPSupply.mul(_percentage).div(1e18);
                    _savedForBoardRoom = _seigniorage.mul(seigniorageExpansionFloorPercent).div(10000);
                    _savedForBond = _seigniorage.sub(_savedForBoardRoom);
                    if (mintingFactorForPayingDebt > 0) {
                        _savedForBond = _savedForBond.mul(mintingFactorForPayingDebt).div(10000);
                    }
                }
                if (_savedForBoardRoom > 0) {
                    _sendToBoardRoom(_savedForBoardRoom);
                }
                if (_savedForBond > 0) {
                    seigniorageSaved = seigniorageSaved.add(_savedForBond);
                    IBasisAsset(CHIP).mint(address(this), _savedForBond);
                    emit TreasuryFunded(block.timestamp, _savedForBond);
                }
            } else {
                // Contraction phase.
                ChipSwapMechanism.unlockFish(4); // When contraction phase, 4 hours worth fish will be unlocked.
                fishPool_v2.set(4, 3000); // Enable MPEA/CHIP pool when contraction phase.
                maxSupplyExpansionPercent = 0;
            }
        }
        if (allocateSeigniorageSalary > 0) {
            IBasisAsset(CHIP).mint(address(msg.sender), allocateSeigniorageSalary);
        }
    }

    function governanceRecoverUnsupported(
        IERC20 _token,
        uint256 _amount,
        address _to
    ) external onlyOperator {
        require(address(_token) != address(CHIP), "CHIP");
        require(address(_token) != address(MPEA), "bond");
        require(address(_token) != address(FISH), "share");
        _token.safeTransfer(_to, _amount);
    }

    // Boardroom controls.

    function boardroomSetOperator(address _operator) external onlyOperator {
        IBoardroom(boardroom).setOperator(_operator);
    }

    function boardroomSetLockUp(uint256 _withdrawLockupEpochs, uint256 _rewardLockupEpochs) external onlyOperator {
        IBoardroom(boardroom).setLockUp(_withdrawLockupEpochs, _rewardLockupEpochs);
    }

    function boardroomAllocateSeigniorage(uint256 amount) external onlyOperator {
        IBoardroom(boardroom).allocateSeigniorage(amount);
    }

    function boardroomGovernanceRecoverUnsupported(
        address _token,
        uint256 _amount,
        address _to
    ) external onlyOperator {
        IBoardroom(boardroom).governanceRecoverUnsupported(_token, _amount, _to);
    }

    // ChipSwap controls.
    function swapChipToFish(uint256 ChipAmount) external {
        uint256 FishPricePerChip = getFishAmountPerChip();
        uint256 FishAmount = ChipAmount.mul(FishPricePerChip).div(1e18);
        ChipSwapMechanism.swap(msg.sender, ChipAmount, FishAmount);
        ERC20Burnable(CHIP).burnFrom(msg.sender, ChipAmount);
    }

    function getFishAmountPerChip() public view returns (uint256) {
        uint256 ChipBalance = IERC20(CHIP).balanceOf(CHIP_BNB);  // CHIP/BNB pool.
        uint256 FishBalance = IERC20(FISH).balanceOf(FISH_BNB);  // FISH/BNB pool.
        uint256 rate1 = uint256(1e18).mul(ChipBalance).div(IERC20(BNB).balanceOf(CHIP_BNB));
        uint256 rate2 = uint256(1e18).mul(FishBalance).div(IERC20(BNB).balanceOf(FISH_BNB));
        return uint256(1e18).mul(rate2).div(rate1);
    }

    function setChipswapMechanism(IChipSwap _chipswapMechanism) external onlyOperator {
        ChipSwapMechanism = _chipswapMechanism;
    }

    function setFishRewardPool(IFishRewardPool _fishPool) external onlyOperator {
        fishPool_v2 = _fishPool;
    }

    function getEpochHistory() external view returns (epochHistory[] memory) {
        return history;
    }

    function setTokenAddress(address _BNB, address _CHIP_BNB, address _FISH_BNB) external onlyOperator {
        BNB = _BNB  ;
        CHIP_BNB = _CHIP_BNB;
        FISH_BNB = _FISH_BNB;
    }
}
