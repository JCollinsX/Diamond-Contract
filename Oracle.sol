// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "./owner/Operator.sol";
import "./lib/Babylonian.sol";
import "./lib/FixedPoint.sol";
import "./lib/PancakeswapOracleLibrary.sol";
import "./interfaces/IEpoch.sol";
import "./interfaces/IPancakePair.sol";

// Note: Fixed window oracle that recomputes the average price for the entire period once every period.
// The price average is only guaranteed to be over at least 1 period, but may be over a longer period.

contract Oracle is IEpoch, Destructor {
    using FixedPoint for *;
    using SafeMath for uint256;

    address public CHIP;
    address public ETH_BNB_LP;
    address public ETH_BUSD_LP;
    IERC20 public ETH;
    IERC20 public BNB;
    IERC20 public BUSD;

    bool public initialized = false;

    IPancakePair public pair; // CHIP/BNB LP
    address public token0;
    address public token1;

    uint32 public blockTimestampLast;
    uint256 public price0CumulativeLast;
    uint256 public price1CumulativeLast;
    FixedPoint.uq112x112 public price0Average;
    FixedPoint.uq112x112 public price1Average;

    IPancakePair public pair_1; // CHIP/BUSD LP
    address public token0_1;
    address public token1_1;

    uint32 public blockTimestampLast_1;
    uint256 public price0CumulativeLast_1;
    uint256 public price1CumulativeLast_1;
    FixedPoint.uq112x112 public price0Average_1;
    FixedPoint.uq112x112 public price1Average_1;

    address public treasury;
    mapping(uint256 => uint256) public epochDollarPrice;
    uint256 public priceAppreciation;

    event Initialized(address indexed executor, uint256 at);
    event Updated(uint256 price0CumulativeLast, uint256 price1CumulativeLast);

    modifier checkEpoch {
        require(block.timestamp >= nextEpochPoint(), "OracleMultiPair: not opened yet");
        _;
    }

    modifier notInitialized {
        require(!initialized, "Treasury: already initialized");
        _;
    }

    function epoch() public view override returns (uint256) {
        return IEpoch(treasury).epoch();
    }

    function nextEpochPoint() public view override returns (uint256) {
        return IEpoch(treasury).nextEpochPoint();
    }

    function nextEpochLength() external view override returns (uint256) {
        return IEpoch(treasury).nextEpochLength();
    }

    function setAddress(
        address _CHIP,
        address _ETH_BNB_LP,
        address _ETH_BUSD_LP,
        IERC20 _ETH,
        IERC20 _BNB,
        IERC20 _BUSD
    ) external onlyOperator {
        CHIP = _CHIP;
        ETH_BNB_LP = _ETH_BNB_LP;
        ETH_BUSD_LP = _ETH_BUSD_LP;
        ETH = _ETH;
        BNB = _BNB;
        BUSD = _BUSD;
    }

    // _pair is CHIP/BNB LP, _pair_1 is CHIP/BUSD LP
    function initialize(IPancakePair _pair, IPancakePair _pair_1) external onlyOperator notInitialized {
        pair = _pair;
        token0 = pair.token0();
        token1 = pair.token1();
        price0CumulativeLast = pair.price0CumulativeLast(); // Fetch the current accumulated price value (1 / 0).
        price1CumulativeLast = pair.price1CumulativeLast(); // Fetch the current accumulated price value (0 / 1).
        uint112 reserve0;
        uint112 reserve1;
        (reserve0, reserve1, blockTimestampLast) = pair.getReserves();
        require(reserve0 != 0 && reserve1 != 0, "Oracle: NO_RESERVES"); // Ensure that there's liquidity in the pair.
        pair_1 = _pair_1;
        token0_1 = pair_1.token0();
        token1_1 = pair_1.token1();
        price0CumulativeLast_1 = pair_1.price0CumulativeLast(); // Fetch the current accumulated price value (1 / 0).
        price1CumulativeLast_1 = pair_1.price1CumulativeLast(); // Fetch the current accumulated price value (0 / 1).
        (reserve0, reserve1, blockTimestampLast_1) = pair_1.getReserves();
        require(reserve0 != 0 && reserve1 != 0, "Oracle: NO_RESERVES"); // Ensure that there's liquidity in the pair.
        initialized = true;
        emit Initialized(msg.sender, block.number);
    }

    function setTreasury(address _treasury) external onlyOperator {
        treasury = _treasury;
    }

    function setPriceAppreciation(uint256 _priceAppreciation) external onlyOperator {
        require(_priceAppreciation <= 2e17, "_priceAppreciation is insane"); // <= 20%
        priceAppreciation = _priceAppreciation;
    }

    // Updates 1-day EMA price from pancakeswap.
    function update() external checkEpoch {
        // CHIP/BNB LP
        (uint256 price0Cumulative, uint256 price1Cumulative, uint32 blockTimestamp) = PancakeswapOracleLibrary.currentCumulativePrices(address(pair));
        uint32 timeElapsed = blockTimestamp - blockTimestampLast; // Overflow is desired.
        if (timeElapsed == 0) {
            // Prevent divided by zero.
            return;
        }
        // Overflow is desired, casting never truncates.
        // Cumulative price is in (uq112x112 price * seconds) units so we simply wrap it after division by time elapsed.
        price0Average = FixedPoint.uq112x112(uint224((price0Cumulative - price0CumulativeLast) / timeElapsed));
        price1Average = FixedPoint.uq112x112(uint224((price1Cumulative - price1CumulativeLast) / timeElapsed));
        price0CumulativeLast = price0Cumulative;
        price1CumulativeLast = price1Cumulative;
        blockTimestampLast = blockTimestamp;
        epochDollarPrice[epoch()] = consult(CHIP, 1e18);
        // CHIP/BUSD LP
        (uint256 price0Cumulative_1, uint256 price1Cumulative_1, uint32 blockTimestamp_1) = PancakeswapOracleLibrary.currentCumulativePrices(address(pair_1));
        uint32 timeElapsed_1 = blockTimestamp_1 - blockTimestampLast_1; // overflow is desired
        if (timeElapsed_1 == 0) {
            // Prevent divided by zero.
            return;
        }
        // Overflow is desired, casting never truncates.
        // Cumulative price is in (uq112x112 price * seconds) units so we simply wrap it after division by time elapsed.
        price0Average_1 = FixedPoint.uq112x112(uint224((price0Cumulative_1 - price0CumulativeLast_1) / timeElapsed_1));
        price1Average_1 = FixedPoint.uq112x112(uint224((price1Cumulative_1 - price1CumulativeLast_1) / timeElapsed_1));
        price0CumulativeLast_1 = price0Cumulative_1;
        price1CumulativeLast_1 = price1Cumulative_1;
        blockTimestampLast_1 = blockTimestamp_1;
        emit Updated(price0Cumulative, price1Cumulative);
    }

    // This will always return 0 before update has been called successfully for the first time.
    // This function returns average of BNB-based and BUSD-based price of CHIP.
    function consult(address _token, uint256 _amountIn) public view returns (uint144 _amountOut) {
        if (priceAppreciation > 0) {
            uint256 _added = _amountIn.mul(priceAppreciation).div(1e18);
            _amountIn = _amountIn.add(_added);
        }
        if (_token == token0) {
            _amountOut = price0Average.mul(_amountIn).decode144();
        } else {
            require(_token == token1, "Oracle: INVALID_TOKEN");
            _amountOut = price1Average.mul(_amountIn).decode144();
        }

        uint144 _amountOut2;
        if (_token == token0_1) {
            _amountOut2 = price0Average_1.mul(_amountIn).decode144();
        } else {
            require(_token == token1_1, "Oracle: INVALID_TOKEN");
            _amountOut2 = price1Average_1.mul(_amountIn).decode144();
        }

        uint256 ETHBalance = ETH.balanceOf(ETH_BNB_LP);
        uint256 BNBBalance = BNB.balanceOf(ETH_BNB_LP);
        uint256 tmp = uint256(_amountOut);
        tmp = tmp.mul(ETHBalance).div(BNBBalance);

        uint256 ETHBalance_1 = ETH.balanceOf(ETH_BUSD_LP);
        uint256 BUSDBalance = BUSD.balanceOf(ETH_BUSD_LP);
        uint256 tmp_1 = uint256(_amountOut2);
        tmp_1 = tmp_1.mul(ETHBalance_1).div(BUSDBalance);

        tmp = tmp.add(tmp_1).div(2);

        _amountOut = uint144(tmp);
    }

    // Twap of CHIP/BNB LP.
    function twap_1(address _token, uint256 _amountIn) internal view returns (uint144 _amountOut) {
        if (priceAppreciation > 0) {
            uint256 _added = _amountIn.mul(priceAppreciation).div(1e18);
            _amountIn = _amountIn.add(_added);
        }
        (uint256 price0Cumulative, uint256 price1Cumulative, uint32 blockTimestamp) = PancakeswapOracleLibrary.currentCumulativePrices(address(pair));
        uint32 timeElapsed = blockTimestamp - blockTimestampLast; // Overflow is desired.
        require(timeElapsed > 0, "Oracle : Elapsed time Error");
        if (_token == token0) {
            require(price0Cumulative >= price0CumulativeLast, "Oracle : Price Calculation Error");
            _amountOut = FixedPoint.uq112x112(uint224((price0Cumulative - price0CumulativeLast) / timeElapsed)).mul(_amountIn).decode144();
        } else if (_token == token1) {
            require(price1Cumulative >= price1CumulativeLast, "Oracle : Price Calculation Error");
            _amountOut = FixedPoint.uq112x112(uint224((price1Cumulative - price1CumulativeLast) / timeElapsed)).mul(_amountIn).decode144();
        }
    }

    // Twap of CHIP/BUSD LP.
    function twap_2(address _token, uint256 _amountIn) internal view returns (uint144 _amountOut) {
        if (priceAppreciation > 0) {
            uint256 _added = _amountIn.mul(priceAppreciation).div(1e18);
            _amountIn = _amountIn.add(_added);
        }
        (uint256 price0Cumulative, uint256 price1Cumulative, uint32 blockTimestamp) = PancakeswapOracleLibrary.currentCumulativePrices(address(pair_1));
        uint32 timeElapsed = blockTimestamp - blockTimestampLast_1; // Overflow is desired.
        require(timeElapsed > 0, "Oracle : Elapsed time Error");
        if (_token == token0_1) {
            require(price0Cumulative >= price0CumulativeLast_1, "Oracle : Price Calculation Error");
            _amountOut = FixedPoint.uq112x112(uint224((price0Cumulative - price0CumulativeLast_1) / timeElapsed)).mul(_amountIn).decode144();
        } else if (_token == token1_1) {
            require(price1Cumulative >= price1CumulativeLast_1, "Oracle : Price Calculation Error");
            _amountOut = FixedPoint.uq112x112(uint224((price1Cumulative - price1CumulativeLast_1) / timeElapsed)).mul(_amountIn).decode144();
        }
    }

    function twap(address _token, uint256 _amountIn) external view returns (uint256 _amountOut) {
        // CHIP/BNB LP, BNB-based price of CHIP.
        uint256 v1 = twap_1(_token, _amountIn);
        // Get ETH-based BNB price.
        uint256 ETHBalance = ETH.balanceOf(ETH_BNB_LP);
        uint256 BNBBalance = BNB.balanceOf(ETH_BNB_LP);
        uint256 ETHPricePerBNB = 1e18;
        ETHPricePerBNB = ETHPricePerBNB.mul(ETHBalance).div(BNBBalance);
        v1 = v1.mul(ETHPricePerBNB).div(1e18);
        // CHIP/BUSD LP, BUSD-based price of CHIP.
        uint256 v2 = twap_2(_token, _amountIn);
        ETHBalance = ETH.balanceOf(ETH_BUSD_LP);
        uint256 BUSDBalance = BUSD.balanceOf(ETH_BUSD_LP);
        uint256 ETHPricePerBUSD = 1e18;
        ETHPricePerBUSD = ETHPricePerBUSD.mul(ETHBalance).div(BUSDBalance);
        v2 = v2.mul(ETHPricePerBUSD).div(1e18);
        _amountOut = v1.add(v2).div(2);
    }
}
