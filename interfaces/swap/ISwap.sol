// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

interface ISwap {
    function swapExactTokensForTokens(
        uint256,
        uint256,
        address[] calldata,
        address,
        uint256
    ) external returns (uint256[] memory amounts);

    function swapTokensForExactTokens(
        uint256,
        uint256,
        address[] calldata,
        address,
        uint256
    ) external returns (uint256[] memory amounts);

    function getAmountsIn(uint256 amountOut, address[] calldata path) 
        external 
        view 
        returns (uint256[] memory amounts);

/*
    function getAmountsOut(uint256 amountIn, address[] memory path)
        external
        view
        returns (uint256[] memory amounts);


    function getAmountIn(uint amountOut, uint reserveIn, uint reserveOut) 
        internal 
        pure 
        returns (uint amountIn);

    function getReserves(address factory, address tokenA, address tokenB) 
        internal 
        view 
        returns (uint reserveA, uint reserveB);
*/
}
