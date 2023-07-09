// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import "woke/console.sol";
import "./IkSwap.sol";

interface IERC20 {
    function transfer(address to, uint256 value) external returns (bool);
    function transferFrom(address from, address to, uint256 value) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

contract kSwapRouter is IkSwapSwapCallback {
    address pool;

    function kSwapCallback(int256 _amount0Delta, int256 _amount1Delta, bytes calldata data) external {
        //msg.sender should be one of our pool addresses - should verify this.
        console.log("Hello world!");
        console.logAddress(pool);
        console.logAddress(msg.sender);
        require(msg.sender == pool, "must be pool we swapped with");
        IkSwapPool p = IkSwapPool(pool);
        console.log("abi decode");
        console.logBytes(data);
        (address from) = abi.decode(data, (address));
        console.log("Payback");
        console.logAddress(from);
        console.logInt(_amount0Delta);
        if (_amount0Delta > 0) {
            IERC20(p.token0()).transferFrom(from, address(p), uint256(_amount0Delta));
        } else {
            IERC20(p.token1()).transferFrom(from, address(p), uint256(_amount1Delta));
        }

        pool = address(0);
    }

    //user must approve the router.
    function swap(address _pool, bool zeroForOne, uint256 amountIn) external returns (uint256) {
        console.log("swap");

        pool = _pool;

        return IkSwapPool(pool).swap(msg.sender, zeroForOne, amountIn, abi.encode(msg.sender));
    }
}
