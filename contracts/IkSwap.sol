// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

interface IkSwapSwapCallback {
    function kSwapCallback(int256 _amount0Delta, int256 _amount1Delta, bytes calldata _data) external;
}

interface IkSwapMintCallback {
    function kMintCallback(uint256 _amount0, uint256 _amount1,address _payer) external;
}

interface IkSwapPool {
    function token0() external view returns (address);
    function token1() external view returns (address);
    function getReserves() external view returns (uint112 _reserve0, uint112 _reserve1);
    function swap(address to, bool zeroForOne, uint256 amountIn, bytes calldata data) external returns (uint256);
    function vulnerable_swap(address to, bool zeroForOne, uint256 amountIn, bytes calldata data) external returns (uint256);

    function mint(address _to, uint256 _amount0,uint256 _amount1) external returns (uint256);

    function previewMint(uint256 _amount0) external view returns(uint256 amount1_);
    function burn(address) external returns (uint256,uint256);

    function quote(uint256 amountIn, uint256 reserveIn, uint256 reserveOut) external pure returns (uint256 amountOut_);
}
