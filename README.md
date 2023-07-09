

# KSwap

# Overview

Simple DEX implementation for the purpose of experimenting with Woke fuzz testing techniques. 





# Fuzz Testing Design







# Dex Pool Implementation





Below is the interface for the pool.  mint and burn are implemented directly from UniswapV2.  The swap functionality borrows elements from UniswapV3, it uses amountIn semantics and the callback interface for sending tokens to the pool.  

```solidity
interface IkSwapSwapCallback {
    function kSwapCallback(int256 _amount0Delta, int256 _amount1Delta, bytes calldata _data) external;
}

interface IkSwapPool {
    function token0() external view returns (address);
    function token1() external view returns (address);
    function getReserves() external view returns (uint112 _reserve0, uint112 _reserve1);
    function swap(address to, bool zeroForOne, uint256 amountIn, bytes calldata data) external returns (uint256);

    function mint() external returns (uint256);
    function burn(address) external returns (uint256,uint256);
}

```





Pool supports



* burn

* mint

* swap

* erc20 interface for the liquidity provider tokens



# Running woke

## Initialize

`woke init pytypes`



## Running regular tests

`woke test tests`






