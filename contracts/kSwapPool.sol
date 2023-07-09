// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import "./IkSwap.sol";
import "./IERC20.sol";
import "./Math.sol";
import "woke/console.sol";

//Tokens are ERC20
//constant product AMM like Uniswap V2.
//Swap borrows elements from Uniswap V3.
//The swap makes a callback to the user.  The user must transfer the input tokens in the callback.

//A lock is used to prevent re-entrancy during the callback.
//For simplicity , there are no Fees
contract kSwapPool is IkSwapPool, IERC20 {
    bytes4 private constant SELECTOR = bytes4(keccak256(bytes('transfer(address,uint256)')));

    function _safeTransfer(address token, address to, uint value) private {
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(SELECTOR, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), 'KSWAP: TRANSFER_FAILED');
    }

    event Mint(address indexed sender, uint amount0, uint amount1);
    event Burn(address indexed sender, uint amount0, uint amount1, address indexed to);    

    event Swap(address user, int256 amount0, int256 amount1);
    //UniswapV2 like storage .  2 tokens, 2 reserves.

    uint8 private constant CONTRACT_UNLOCKED = 1;
    uint8 private constant CONTRACT_LOCKED = 2;

    address public token0;
    address public token1;

    uint112 private reserve0;
    uint112 private reserve1;
    uint8 private lockStatus = CONTRACT_UNLOCKED;

    string public constant name = "KSWAP";
    string public constant symbol = "KSWAP";
    uint8 public constant decimals = 18;
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    modifier lock() {
        require(lockStatus == CONTRACT_UNLOCKED, "kSwap: LOCKED");
        lockStatus = CONTRACT_LOCKED;
        _;
        lockStatus = CONTRACT_UNLOCKED;
    }

    function getReserves() public view returns (uint112 _reserve0, uint112 _reserve1) {
        _reserve0 = reserve0;
        _reserve1 = reserve1;
    }

    function _mint(address to, uint256 value) internal {
        totalSupply = totalSupply += value;
        balanceOf[to] = balanceOf[to] += value;
        emit Transfer(address(0), to, value);
    }

    function _burn(address from, uint256 value) internal {
        balanceOf[from] = balanceOf[from] - value;
        totalSupply = totalSupply - value;
        emit Transfer(from, address(0), value);
    }

    function _approve(address owner, address spender, uint256 value) private {
        allowance[owner][spender] = value;
        emit Approval(owner, spender, value);
    }

    function _transfer(address from, address to, uint256 value) private {
        balanceOf[from] = balanceOf[from] - value;
        balanceOf[to] = balanceOf[to] + value;
        emit Transfer(from, to, value);
    }

    function approve(address spender, uint256 value) external returns (bool) {
        _approve(msg.sender, spender, value);
        return true;
    }

    function transfer(address to, uint256 value) external returns (bool) {
        _transfer(msg.sender, to, value);
        return true;
    }

    function transferFrom(address from, address to, uint256 value) external returns (bool) {
        if (allowance[from][msg.sender] != type(uint256).max) {
            allowance[from][msg.sender] = allowance[from][msg.sender] - value;
        }
        _transfer(from, to, value);
        return true;
    }

    function getAmountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut)
        internal
        view
        returns (
            // pure
            uint256
        )
    {
        require(reserveIn > 0, "kSwap: INSUFFICIENT_LIQUIDITY");
        require(reserveOut > 0, "kSwap: INSUFFICIENT_LIQUIDITY");

        uint256 numerator = amountIn * reserveOut;
        uint256 denominator = reserveIn + amountIn;
        console.logUint(numerator);
        console.logUint(denominator);
        //  console.logUint(reserveIn*reserveOut);
        return numerator / denominator;
    }

    constructor(address _token0, address _token1) {
        token0 = _token0;
        token1 = _token1;
    }

    //Right now , this is just added for initializing liquidity in testing.
    //A real mint would need to find the difference between current reserves and balance
    //and then return a token or nft representing the liquidity position
    function mint() external lock returns (uint256 liquidity) {
        (uint112 _reserve0, uint112 _reserve1) = getReserves(); // gas savings
        uint256 balance0 = IERC20(token0).balanceOf(address(this));
        uint256 balance1 = IERC20(token1).balanceOf(address(this));
        uint256 amount0 = balance0 - _reserve0;
        uint256 amount1 = balance1 - _reserve1;

        uint256 _totalSupply = totalSupply; // gas savings, must be defined here since totalSupply can update in _mintFee
        if (_totalSupply == 0) {
            liquidity = Math.sqrt(amount0 * amount1);
        } else {
            liquidity = Math.min(amount0 * _totalSupply / _reserve0, amount1 * _totalSupply / _reserve1);
        }
        require(liquidity > 0, "KSWAP: INSUFFICIENT_LIQUIDITY_MINTED");
        _mint(msg.sender, liquidity);
        reserve0 = uint112(IERC20(token0).balanceOf(address(this)));
        reserve1 = uint112(IERC20(token1).balanceOf(address(this)));
        console.log("minting");
        emit Mint(msg.sender, amount0, amount1);
    }

   // this low-level function should be called from a contract which performs important safety checks
    function burn(address to) external lock returns (uint amount0, uint amount1) {
        (uint112 _reserve0, uint112 _reserve1) = getReserves(); // gas savings
        address _token0 = token0;                                // gas savings
        address _token1 = token1;                                // gas savings
        uint balance0 = IERC20(_token0).balanceOf(address(this));
        uint balance1 = IERC20(_token1).balanceOf(address(this));
        uint liquidity = balanceOf[address(this)];

        uint _totalSupply = totalSupply; // gas savings, must be defined here since totalSupply can update in _mintFee
        amount0 = (liquidity  * balance0) / _totalSupply; // using balances ensures pro-rata distribution
        amount1 = (liquidity * balance1) / _totalSupply; // using balances ensures pro-rata distribution
        require(amount0 > 0 && amount1 > 0, 'KSWAP: INSUFFICIENT_LIQUIDITY_BURNED');
        _burn(address(this), liquidity);
        _safeTransfer(_token0, to, amount0);
        _safeTransfer(_token1, to, amount1);
        balance0 = IERC20(_token0).balanceOf(address(this));
        balance1 = IERC20(_token1).balanceOf(address(this));

        reserve0 = uint112(balance0);
        reserve1 = uint112(balance1);

        emit Burn(msg.sender, amount0, amount1, to);
    }


    // this low-level function should be called from a contract which performs important safety checks
    function swap(address to, bool zeroForOne, uint256 amountIn, bytes calldata data) external lock returns (uint256) {
        console.log("pool swaps");
        require(amountIn != 0, "kSwap 0 Start ");
        (uint112 _reserve0, uint112 _reserve1) = getReserves(); // gas savings

        require(to != token0 && to != token1, "kSwap: INVALID_TO");
        console.log("amt out");
        console.logUint(_reserve0);
        console.logUint(_reserve1);
        (int256 amount0_, int256 amount1_) = zeroForOne
            ? (int256(amountIn), -int256(getAmountOut(amountIn, _reserve0, _reserve1)))
            : (-int256(getAmountOut(amountIn, _reserve1, _reserve0)), int256(amountIn));

        address inToken = zeroForOne ? token0 : token1;
        address outToken = zeroForOne ? token1 : token0;
        uint256 balanceIn = IERC20(inToken).balanceOf(address(this));
        //erc20 transfer output token
        console.log("transfer");
        console.logInt(amount0_);
        console.logInt(amount1_);

        if (zeroForOne) {
            IERC20(token1).transfer(to, uint256(-amount1_));
        } else {
            IERC20(token0).transfer(to, uint256(-amount0_));
        }
        console.log("callback");
        IkSwapSwapCallback(msg.sender).kSwapCallback(amount0_, amount1_, data);

        //verify that input token was transferred
        uint256 balanceOut = IERC20(inToken).balanceOf(address(this));
        console.logUint(balanceOut);
        console.logUint(balanceIn);
        require(balanceIn + amountIn <= balanceOut, "IIA");
        uint256 balance1 = IERC20(outToken).balanceOf(address(this));
        require(balanceOut <= type(uint112).max && balance1 <= type(uint112).max, "kSwap: OVERFLOW");

        //update reserves
        if (zeroForOne) {
            reserve0 = uint112(balanceOut);
            reserve1 = uint112(balance1);
        } else {
            reserve1 = uint112(balanceOut);
            reserve0 = uint112(balance1);
        }
        console.log("reserves");
        console.logUint(reserve0);
        console.logUint(reserve1);
        emit Swap(msg.sender, amount0_, amount1_);
        return zeroForOne ? uint256(-amount1_) : uint256(-amount0_);
    }
}