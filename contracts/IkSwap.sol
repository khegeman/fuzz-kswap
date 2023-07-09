// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

interface IkSwapSwapCallback {
    function kSwapCallback(int256 _amount0Delta, int256 _amount1Delta, bytes calldata _data) external;
}

interface IkSwapPool {
    function token0() external view returns (address);
    function token1() external view returns (address);
    function getReserves() external view returns (uint112 _reserve0, uint112 _reserve1);
    function swap(address to, bool zeroForOne, uint256 amountIn, bytes calldata data) external returns (uint256);
}
