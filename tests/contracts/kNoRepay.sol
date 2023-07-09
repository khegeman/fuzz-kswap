// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import "contracts/IkSwap.sol";
import "contracts/IERC20.sol";

contract kCheckNoRepay is IkSwapSwapCallback {
   
    function kSwapCallback(int256 _amount0Delta, int256 _amount1Delta, bytes calldata data) external {
    
    }


    function swap(address _pool, bool zeroForOne, uint256 amountIn) external returns (uint256) {

    
        return IkSwapPool(_pool).swap(msg.sender, zeroForOne, amountIn, abi.encode(msg.sender));
    }
}
