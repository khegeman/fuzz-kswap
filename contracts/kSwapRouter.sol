// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import "./IkSwap.sol";
import "./IERC20.sol";

contract kSwapRouter is IkSwapSwapCallback {
    address pool;

    function kSwapCallback(int256 _amount0Delta, int256 _amount1Delta, bytes calldata data) external {
        //msg.sender should be one of our pool addresses - should verify this.
        require(msg.sender == pool, "must be pool we swapped with");
        IkSwapPool p = IkSwapPool(pool);
        (address from) = abi.decode(data, (address));
        if (_amount0Delta > 0) {
            IERC20(p.token0()).transferFrom(from, address(p), uint256(_amount0Delta));
        } else {
            IERC20(p.token1()).transferFrom(from, address(p), uint256(_amount1Delta));
        }

        pool = address(0);
    }

    //user must approve the router.
    function swap(address _pool, bool zeroForOne, uint256 amountIn) external returns (uint256) {

        pool = _pool;

        return IkSwapPool(pool).swap(msg.sender, zeroForOne, amountIn, abi.encode(msg.sender));
    }
}
