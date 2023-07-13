# KSwap

# Overview

Simple DEX implementation for the purpose of experimenting with stateful fuzz test design and implementation using the Woke framework.



# Constant Product AMM

The dex pool is a constant product AMM, based primarily on the Uniswap V2 model.  


It also builds on some ideas from UniswapV3 and Smardex

 [GitHub - SmarDex-Dev/smart-contracts](https://github.com/SmarDex-Dev/smart-contracts/tree/main)[GitHub - SmarDex-Dev/smart-contracts](https://github.com/SmarDex-Dev/smart-contracts/tree/main)

## Pool supports

- burn

- mint

- swap

- erc20 interface for the liquidity provider tokens

## Dex Pool Implementation

Below is the interface for the pool. Tmint and burn are implemented directly from UniswapV2. The mint and swap functionality borrows elements from UniswapV3 where a callback mechanism is used when the user needs to transfer tokens to the pool.  The interface also uses amountIn semantics for swapping.

```solidity
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
    function swap(address _to, bool _zeroForOne, uint256 _amountIn, bytes calldata _data) external returns (uint256);
    function mint(address _to, uint256 _amount0,uint256 _amount1) external returns (uint256);

    function previewMint(uint256 _amount0) external view returns(uint256 amount1_);
    function burn(address) external returns (uint256,uint256);

    function quote(uint256 _amountIn, uint256 _reserveIn, uint256 _reserveOut) external pure returns (uint256 amountOut_);
}
```



# Fuzz Testing Design

Starting with 3 flows and a single pool.


* add liquidity to the pool
* burn liquidity from the pool
* swap tokens in the pool.
* Check the constant product protocol invariant after each flow.



## Sample Sequence Of The Fuzz Test



These are the flows of a 10 step sequence.  Each flow has input parameters generated randomly by woke.  These steps emulate users minting, burning and swapping in random permutations.

```
seq: 0 flow: 0 flow name: flow_mint flow parameters:
{'to_': 0x8ab3dc1d2d61394a07391d91021928c683b0fd4d, 'amount0': 36747731846}
seq: 0 flow: 1 flow name: flow_mint flow parameters:
{'to_': 0x1bf1a0d2f84a085862187a79ea30302142bf3fc6, 'amount0': 6032415366}
seq: 0 flow: 2 flow name: flow_swap flow parameters:
{'to_': 0x8ab3dc1d2d61394a07391d91021928c683b0fd4d, 'zeroForOne': False, 'amount': 32740912904}
seq: 0 flow: 3 flow name: flow_mint flow parameters:
{'to_': 0x609767c4b0ab535b1256d7489e281c8211961845, 'amount0': 38677884889}
seq: 0 flow: 4 flow name: flow_swap flow parameters:
{'to_': 0x8ab3dc1d2d61394a07391d91021928c683b0fd4d, 'zeroForOne': True, 'amount': 9766379329}
seq: 0 flow: 5 flow name: flow_burn flow parameters:
{'to_': 0x609767c4b0ab535b1256d7489e281c8211961845}
seq: 0 flow: 6 flow name: flow_burn flow parameters:
{'to_': 0x8ab3dc1d2d61394a07391d91021928c683b0fd4d}
seq: 0 flow: 7 flow name: flow_mint flow parameters:
{'to_': 0x1bf1a0d2f84a085862187a79ea30302142bf3fc6, 'amount0': 38640011899}
seq: 0 flow: 8 flow name: flow_burn flow parameters:
{'to_': 0x8a263b7b74fecbbcaffe589dd1f9d6bc0b472802}
seq: 0 flow: 9 flow name: flow_mint flow parameters:
{'to_': 0xacf5d1ae6fb509bdb6b1bcd8a7cf545ed478a174, 'amount0': 19289289414}
```



# Re-entrancy



## Protection



The mint, burn and swap functions are protected by a re-entrancy guard modifier on the pool.  This follows the design of UniswapV2. 


```solidity
    modifier lock() {
        if (lockStatus != CONTRACT_UNLOCKED) {
            revert ContractLocked();
        }

        lockStatus = CONTRACT_LOCKED;
        _;
        lockStatus = CONTRACT_UNLOCKED;
    }

```



## Re-entrancy Experiment



I added an additional swap method to the dex that doesn't protect itself with a lock.  I then designed a simple exploit and I used the fuzz test suite to verify that the tests can catch errors such as this.  



This vulnerable_swap method does not have the lock modifier on it in the implementation

```solidity

function vulnerable_swap(address _to, bool _zeroForOne, uint256 _amountIn, bytes calldata _data) external returns (uint256);
```




The callback to the user occurs before the reserves are updated.  Without the lock, the user can initiate a 2nd swap inside the callback.  As such, the user transfers tokens to the pool one time and the pool sends tokens to the user twice.  At the end of this transaction, the constant product invariant does not hold and the fuzz test generates an error.

```solidity
//Lauches a basic Re-entrancy Attack on a pool with unlocked swap function
contract kReenter is IkSwapSwapCallback {
   
    function kSwapCallback(int256 _amount0Delta, int256 _amount1Delta, bytes calldata data) external {
            
        IkSwapPool p = IkSwapPool(msg.sender);
        (bool reenter, address from,bool zeroForOne,uint256 amountIn) = abi.decode(data, (bool,address,bool,uint256));
        if (reenter) { 
            //resend the same swap a 2nd time before the first one completes
            p.vulnerable_swap(from, zeroForOne, amountIn, abi.encode(false,from,zeroForOne,amountIn));
        } else {
            //send the payment
            if (_amount0Delta > 0) {
                IERC20(p.token0()).transferFrom(from, address(p), uint256(_amount0Delta));
            } else {
                IERC20(p.token1()).transferFrom(from, address(p), uint256(_amount1Delta));
            }
        }

    }


    function swap(address _pool, bool zeroForOne, uint256 amountIn) external returns (uint256) {

    
        return IkSwapPool(_pool).vulnerable_swap(msg.sender, zeroForOne, amountIn, abi.encode(true,msg.sender,zeroForOne,amountIn));
    }
}
```











# Running woke

## Initialize

`woke init pytypes`

## Configuration

create a .env file with the following url that points to alchemy.  This is used to create a local fork of mainnet for testing

```
RPC_URL=https://eth-mainnet.g.alchemy.com/v2/
```

## Running tests

`woke test `





# Future Work

Overflow is not tested right now.  Instead of using existing ERC20 tokens, create fake ERC20 tokens that we control the supply for.  Allow the operations on mint  / swap to add more liquidity than the 112 bits used for reserves.
