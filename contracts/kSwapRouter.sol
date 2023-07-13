// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import "./IkSwap.sol";
import "./IERC20.sol";

contract kSwapRouter is IkSwapSwapCallback, IkSwapMintCallback {
    address pool;

    function kSwapCallback(int256 _amount0Delta, int256 _amount1Delta, bytes calldata _data) external {
        //msg.sender should be one of our pool addresses - should verify this.
        //this is commonly done via a factory to check if the address is known to the protocol.
        require(msg.sender == pool, "must be pool we swapped with");
        IkSwapPool p = IkSwapPool(pool);
        (address from) = abi.decode(_data, (address));
        if (_amount0Delta > 0) {
            IERC20(p.token0()).transferFrom(from, address(p), uint256(_amount0Delta));
        } else {
            IERC20(p.token1()).transferFrom(from, address(p), uint256(_amount1Delta));
        }

        pool = address(0);
    }

    function kMintCallback(uint256 _amount0, uint256 _amount1, address _payer) external {
        //msg.sender should be one of our pool addresses - should verify this.
        //this is commonly done via a factory to check if the address is known to the protocol.
        require(msg.sender == pool, "must be pool we minted to");
        IkSwapPool p = IkSwapPool(pool);

        if (_amount0 > 0) {
            IERC20(p.token0()).transferFrom(_payer, address(p), uint256(_amount0));
        }
        if (_amount1 > 0) {
            IERC20(p.token1()).transferFrom(_payer, address(p), uint256(_amount1));
        }

        pool = address(0);
    }

    //user must approve the router.
    function swap(address _pool, bool _zeroForOne, uint256 _amountIn) external returns (uint256) {
        pool = _pool;

        return IkSwapPool(pool).swap(msg.sender, _zeroForOne, _amountIn, abi.encode(msg.sender));
    }

    function addLiquidity(
        address _pool,
        uint256 _amountADesired,
        uint256 _amountBDesired,
        uint256 _amountAMin,
        uint256 _amountBMin
    ) external returns (uint256 amount0_, uint256 amount1_, uint256 liquidity_) {
        pool = _pool;

        (amount0_, amount1_) = _addLiquidity(_pool, _amountADesired, _amountBDesired, _amountAMin, _amountBMin);
        //IERC20(IkSwapPool(pool).token0()).transferFrom(msg.sender, _pool, amount0_);
        //IERC20(IkSwapPool(pool).token1()).transferFrom(msg.sender, _pool, amount1_);
        liquidity_ = IkSwapPool(pool).mint(msg.sender, amount0_, amount1_);
    }

    function _addLiquidity(
        address _pool,
        uint256 _amount0Desired,
        uint256 _amount1Desired,
        uint256 _amount0Min,
        uint256 _amount1Min
    ) internal virtual returns (uint256 amount0_, uint256 amount1_) {
        (uint256 _reserve0, uint256 _reserve1) = IkSwapPool(pool).getReserves();
        if (_reserve0 == 0 && _reserve1 == 0) {
            (amount0_, amount1_) = (_amount0Desired, _amount1Desired);
        } else {
            uint256 _amount1Optimal = IkSwapPool(pool).quote(_amount0Desired, _reserve0, _reserve1);
            if (_amount1Optimal <= _amount1Desired) {
                require(_amount1Optimal >= _amount1Min, "SmarDexRouter: INSUFFICIENT_B_AMOUNT");
                (amount0_, amount1_) = (_amount0Desired, _amount1Optimal);
            } else {
                uint256 _amount0Optimal = IkSwapPool(pool).quote(_amount1Desired, _reserve1, _reserve0);
                assert(_amount0Optimal <= _amount0Desired);
                require(_amount0Optimal >= _amount0Min, "SmarDexRouter: INSUFFICIENT_A_AMOUNT");
                (amount0_, amount1_) = (_amount0Optimal, _amount1Desired);
            }
        }
    }
}
