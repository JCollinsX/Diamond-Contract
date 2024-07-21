// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import { IUniswapV2Router02 } from "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { ISwapRouterV3 } from "../interfaces/ISwapRouterV3.sol";
import { IUniswapV3Pool } from "../interfaces/IUniswapV3Pool.sol";

library LibSwapTokens {
    using SafeERC20 for IERC20;

    function _swapEthForExactTokensV2(uint256 ethAmount, address token, uint256 amountOut, address router) internal {
        address[] memory path = new address[](2);
        path[0] = IUniswapV2Router02(router).WETH();
        path[1] = address(token);
        IUniswapV2Router02(router).swapETHForExactTokens{ value: ethAmount }(amountOut, path, address(this), block.timestamp);
    }

    function _swapEthForExactTokensV3(uint256 ethAmount, address token, uint256 amountOut, address router, uint24 v3PoolFee) internal {
        ISwapRouterV3.ExactOutputSingleParams memory params = ISwapRouterV3.ExactOutputSingleParams({
            tokenIn: ISwapRouterV3(router).WETH9(),
            tokenOut: token,
            fee: v3PoolFee,
            recipient: address(this),
            amountOut: amountOut,
            amountInMaximum: ethAmount,
            sqrtPriceLimitX96: 0
        });
        uint256 amountIn = ISwapRouterV3(router).exactOutputSingle{ value: ethAmount }(params);

        if (amountIn < ethAmount) {
            ISwapRouterV3(router).refundETH();
        }
    }

    function _swapExactTokensForTokensV2(address inputToken, address outputToken, uint256 inputAmount, address treasury, address router) internal {
        address[] memory path = new address[](3);
        path[0] = inputToken;
        path[1] = IUniswapV2Router02(router).WETH();
        path[2] = outputToken;
        if (IERC20(inputToken).allowance(address(this), router) != 0) {
            IERC20(inputToken).safeApprove(router, 0);
        }
        IERC20(inputToken).safeApprove(router, inputAmount);

        IUniswapV2Router02(router).swapExactTokensForTokensSupportingFeeOnTransferTokens(inputAmount, 0, path, treasury, block.timestamp);
    }

    function _swapTokensForExactTokensV2(
        address inputToken,
        uint256 amountInMax,
        address outputToken,
        uint256 amountOut,
        address treasury,
        address router
    ) internal {
        address[] memory path = new address[](3);
        path[0] = inputToken;
        path[1] = IUniswapV2Router02(router).WETH();
        path[2] = outputToken;
        if (IERC20(inputToken).allowance(address(this), router) != 0) {
            IERC20(inputToken).safeApprove(router, 0);
        }

        IERC20(inputToken).safeApprove(router, amountInMax);

        uint256[] memory requiredAmounts = IUniswapV2Router02(router).getAmountsIn(amountOut, path);
        require(requiredAmounts[0] <= amountInMax, "LibSwapTokens: INSUFFICIENT_INPUT_AMOUNT");

        IUniswapV2Router02(router).swapTokensForExactTokens(amountOut, amountInMax, path, treasury, block.timestamp);
    }

    function _swapExactTokensForTokensV3(
        address inputToken,
        address outputToken,
        uint256 inputAmount,
        uint24 inputTokenPoolFee,
        uint24 outputTokenPoolFee,
        address treasury,
        address router
    ) internal {
        if (IERC20(inputToken).allowance(address(this), router) != 0) {
            IERC20(inputToken).safeApprove(router, 0);
        }
        IERC20(inputToken).safeApprove(router, inputAmount);

        bytes memory path = abi.encodePacked(inputToken, inputTokenPoolFee, ISwapRouterV3(router).WETH9(), outputTokenPoolFee, outputToken);

        ISwapRouterV3.ExactInputParams memory params = ISwapRouterV3.ExactInputParams({
            path: path,
            recipient: treasury,
            amountIn: inputAmount,
            amountOutMinimum: 0
        });

        ISwapRouterV3(router).exactInput(params);
    }

    function _swapTokensForExactTokensV3(
        address inputToken,
        uint256 amountInMax,
        address outputToken,
        uint256 amountOut,
        uint24 inputTokenPoolFee,
        uint24 outputTokenPoolFee,
        address treasury,
        address router
    ) internal {
        if (IERC20(inputToken).allowance(address(this), router) != 0) {
            IERC20(inputToken).safeApprove(router, 0);
        }
        IERC20(inputToken).safeApprove(router, amountInMax);

        bytes memory path = abi.encodePacked(outputToken, outputTokenPoolFee, ISwapRouterV3(router).WETH9(), inputTokenPoolFee, inputToken);

        ISwapRouterV3.ExactOutputParams memory params = ISwapRouterV3.ExactOutputParams({
            path: path,
            recipient: treasury,
            amountOut: amountOut,
            amountInMaximum: amountInMax
        });

        ISwapRouterV3(router).exactOutput(params);
    }

    function _getQuoteTokenPriceV2Weth(address token0, address token1, address router) internal view returns (uint256) {
        address[] memory path = new address[](2);
        path[0] = token1;
        path[1] = token0;
        uint256 token0Unit = 10 ** IERC20Metadata(token0).decimals();
        uint256[] memory amounts = IUniswapV2Router02(router).getAmountsIn(token0Unit, path);

        return amounts[0];
    }
    function _getQuoteTokenPriceV2(address token0, address token1, address router) internal view returns (uint256) {
        address weth = IUniswapV2Router02(router).WETH();
        if (token0 == address(0)) {
            return _getQuoteTokenPriceV2Weth(weth, token1, router);
        } else if (token1 == address(0)) {
            return _getQuoteTokenPriceV2Weth(token0, weth, router);
        }

        address[] memory path = new address[](3);
        path[0] = token1;
        path[1] = IUniswapV2Router02(router).WETH();
        path[2] = token0;

        uint256 token0Unit = 10 ** IERC20Metadata(token0).decimals();
        uint256[] memory amounts = IUniswapV2Router02(router).getAmountsIn(token0Unit, path);

        return amounts[0];
    }

    function _shiftRightBits(uint256 value) internal pure returns (uint256 result, uint256 bits) {
        uint256 maxNumber = 1 << 128;
        result = value;
        if (result >= maxNumber) {
            for (bits = 1; bits <= 96; bits++) {
                result = (value >> bits);
                if (result < maxNumber) {
                    return (result, bits);
                }
            }
        }
    }

    function _getTokenPriceFromSqrtX96(uint256 sqrtPrice) internal pure returns (uint256 price) {
        (uint256 bitResult, uint256 bits) = _shiftRightBits(sqrtPrice);
        uint256 leftBits = (96 - bits) * 2;
        price = (bitResult * bitResult);
        (price, bits) = _shiftRightBits(price);
        leftBits -= bits;
        price = (price * 1e18) >> leftBits;
    }

    function _getQuoteTokenPriceV3Weth(address token, uint24 poolFee, address router) internal view returns (uint256, uint256) {
        address weth = ISwapRouterV3(router).WETH9();
        address factory = ISwapRouterV3(router).factory();
        address pool = ISwapRouterV3(factory).getPool(weth, token, poolFee);
        uint256 tokenDecimals = IERC20Metadata(token).decimals();

        address poolToken0 = IUniswapV3Pool(pool).token0();
        (uint160 sqrtPriceX96, , , , , , ) = IUniswapV3Pool(pool).slot0();

        uint256 tokenPerWeth = _getTokenPriceFromSqrtX96(sqrtPriceX96);
        uint256 wethPerToken = (10 ** (18 + tokenDecimals)) / tokenPerWeth;

        if (poolToken0 == weth) {
            return (tokenPerWeth, wethPerToken);
        } else {
            return (wethPerToken, tokenPerWeth);
        }
    }

    function _getQuoteTokenPriceV3(address token0, address token1, uint24 token0PoolFee, uint24 token1PoolFee, address router) internal view returns (uint256) {
        uint256 wethPerToken;
        uint256 tokenPerWeth;
        if (token0 == address(0)) {
            (tokenPerWeth, ) = _getQuoteTokenPriceV3Weth(token1, token1PoolFee, router);
            return tokenPerWeth;
        } else if (token1 == address(0)) {
            (, wethPerToken) = _getQuoteTokenPriceV3Weth(token0, token0PoolFee, router);
            return wethPerToken;
        }

        (, wethPerToken) = _getQuoteTokenPriceV3Weth(token0, token0PoolFee, router);
        (tokenPerWeth, ) = _getQuoteTokenPriceV3Weth(token1, token1PoolFee, router);

        return (wethPerToken * tokenPerWeth) / 1e18;
    }
}
