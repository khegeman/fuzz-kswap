// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import "./IkSwap.sol";
import "./IERC20.sol";
import "./Math.sol";

//Tokens are ERC20
//constant product AMM like Uniswap V2.
//Swap borrows elements from Uniswap V3.
//The swap makes a callback to the user.  The user must transfer the input tokens in the callback.

//A lock is used to prevent re-entrancy during the callback.
//For simplicity , there are no Fees
contract kSwapPool is IkSwapPool, IERC20 {
    bytes4 private constant SELECTOR = bytes4(keccak256(bytes("transfer(address,uint256)")));

    error TransferFailed();
    error ContractLocked();
    error InsufficientLiquidity();
    error InsufficientLiquidityMinted();
    error InsufficientLiquidityBurned();
    error InsufficientInputAmount();
    error SwapOverflow();
    error AmountIn0();
    error InvalidTo();

    function _safeTransfer(address _token, address _to, uint256 _value) private {
        (bool success, bytes memory data) = _token.call(abi.encodeWithSelector(SELECTOR, _to, _value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), "KSWAP: TRANSFER_FAILED");
    }

    event Mint(address indexed sender, uint256 amount0, uint256 amount1);
    event Burn(address indexed sender, uint256 amount0, uint256 amount1, address indexed to);

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
        if (lockStatus != CONTRACT_UNLOCKED) {
            revert ContractLocked();
        }

        lockStatus = CONTRACT_LOCKED;
        _;
        lockStatus = CONTRACT_UNLOCKED;
    }

    function getReserves() public view returns (uint112 reserve0_, uint112 reserve1_) {
        reserve0_ = reserve0;
        reserve1_ = reserve1;
    }

    function _mint(address _to, uint256 _value) internal {
        totalSupply = totalSupply += _value;
        balanceOf[_to] = balanceOf[_to] += _value;
        emit Transfer(address(0), _to, _value);
    }

    function _burn(address _from, uint256 _value) internal {
        balanceOf[_from] = balanceOf[_from] - _value;
        totalSupply = totalSupply - _value;
        emit Transfer(_from, address(0), _value);
    }

    function _approve(address _owner, address _spender, uint256 _value) private {
        allowance[_owner][_spender] = _value;
        emit Approval(_owner, _spender, _value);
    }

    function _transfer(address _from, address _to, uint256 _value) private {
        balanceOf[_from] = balanceOf[_from] - _value;
        balanceOf[_to] = balanceOf[_to] + _value;
        emit Transfer(_from, _to, _value);
    }

    function approve(address _spender, uint256 _value) external returns (bool) {
        _approve(msg.sender, _spender, _value);
        return true;
    }

    function transfer(address _to, uint256 _value) external returns (bool) {
        _transfer(msg.sender, _to, _value);
        return true;
    }

    function transferFrom(address _from, address _to, uint256 _value) external returns (bool) {
        if (allowance[_from][msg.sender] != type(uint256).max) {
            allowance[_from][msg.sender] = allowance[_from][msg.sender] - _value;
        }
        _transfer(_from, _to, _value);
        return true;
    }

    function quote(uint256 _amountIn, uint256 _reserveIn, uint256 _reserveOut)
        public
        pure
        returns (uint256 amountOut_)
    {
        if (_amountIn == 0) {
            revert AmountIn0();
        }
        if (_reserveIn == 0) {
            revert InsufficientLiquidity();
        }
        if (_reserveOut == 0) {
            revert InsufficientLiquidity();
        }
        amountOut_ = (_amountIn * _reserveOut) / _reserveIn;
    }

    function getAmountOut(uint256 _amountIn, uint256 _reserveIn, uint256 _reserveOut) internal pure returns (uint256) {
        if (_reserveIn == 0) {
            revert InsufficientLiquidity();
        }
        if (_reserveOut == 0) {
            revert InsufficientLiquidity();
        }

        uint256 numerator = _amountIn * _reserveOut;
        uint256 denominator = _reserveIn + _amountIn;
        return numerator / denominator;
    }

    constructor(address _token0, address _token1) {
        token0 = _token0;
        token1 = _token1;
    }

    function previewMint(uint256 _amount0) external view returns (uint256 amount1_) {
        amount1_ = quote(_amount0, reserve0, reserve1);
    }
    //Right now , this is just added for initializing liquidity in testing.
    //A real mint would need to find the difference between current reserves and balance
    //and then return a token or nft representing the liquidity position

    function mint(address _to, uint256 _amount0, uint256 _amount1) external lock returns (uint256 liquidity) {
        (uint112 _reserve0, uint112 _reserve1) = getReserves(); // gas savings
        uint256 balance0 = IERC20(token0).balanceOf(address(this));
        uint256 balance1 = IERC20(token1).balanceOf(address(this));
        uint256 amount0 = _amount0; //balance0 - _reserve0;
        uint256 amount1 = _amount1; //balance1 - _reserve1;

        uint256 _totalSupply = totalSupply; // gas savings, must be defined here since totalSupply can update in _mintFee
        if (_totalSupply == 0) {
            liquidity = Math.sqrt(amount0 * amount1);
        } else {
            liquidity = Math.min(amount0 * _totalSupply / _reserve0, amount1 * _totalSupply / _reserve1);
        }
        if (liquidity == 0) {
            revert InsufficientLiquidityMinted();
        }
        IkSwapMintCallback(msg.sender).kMintCallback(amount0, amount1, _to);
        //callback must send the required tokens to the contract before we mint
        require(IERC20(token0).balanceOf(address(this)) >= balance0 + amount0);
        require(IERC20(token1).balanceOf(address(this)) >= balance1 + amount1);

        _mint(_to, liquidity);
        reserve0 = uint112(IERC20(token0).balanceOf(address(this)));
        reserve1 = uint112(IERC20(token1).balanceOf(address(this)));

        emit Mint(_to, amount0, amount1);
    }

    // this low-level function should be called from a contract which performs important safety checks
    function burn(address _to) external lock returns (uint256 amount0_, uint256 amount1_) {
        address _token0 = token0; // gas savings
        address _token1 = token1; // gas savings
        uint256 balance0 = IERC20(_token0).balanceOf(address(this));
        uint256 balance1 = IERC20(_token1).balanceOf(address(this));
        uint256 liquidity = balanceOf[address(this)];

        uint256 _totalSupply = totalSupply; // gas savings, must be defined here since totalSupply can update in _mintFee
        if (_totalSupply == 0) {
            revert InsufficientLiquidityBurned();
        }
        amount0_ = (liquidity * balance0) / _totalSupply; // using balances ensures pro-rata distribution
        amount1_ = (liquidity * balance1) / _totalSupply; // using balances ensures pro-rata distribution
        if (amount0_ == 0) {
            revert InsufficientLiquidityBurned();
        }
        if (amount1_ == 0) {
            revert InsufficientLiquidityBurned();
        }

        _burn(address(this), liquidity);
        _safeTransfer(_token0, _to, amount0_);
        _safeTransfer(_token1, _to, amount1_);
        balance0 = IERC20(_token0).balanceOf(address(this));
        balance1 = IERC20(_token1).balanceOf(address(this));

        reserve0 = uint112(balance0);
        reserve1 = uint112(balance1);

        emit Burn(msg.sender, amount0_, amount1_, _to);
    }

    function swap(address _to, bool _zeroForOne, uint256 _amountIn, bytes calldata _data)
        external
        lock
        returns (uint256)
    {
        return _swap(_to, _zeroForOne, _amountIn, _data);
    }

    //for testing, this version doesn't lock the contract.
    function vulnerable_swap(address _to, bool _zeroForOne, uint256 _amountIn, bytes calldata _data)
        external
        returns (uint256)
    {
        return _swap(_to, _zeroForOne, _amountIn, _data);
    }

    function _swap(address _to, bool _zeroForOne, uint256 _amountIn, bytes calldata _data) internal returns (uint256) {
        if (_amountIn == 0) {
            revert AmountIn0();
        }

        (uint112 _reserve0, uint112 _reserve1) = getReserves(); // gas savings

        if (_to == token0) {
            revert InvalidTo();
        }
        if (_to == token1) {
            revert InvalidTo();
        }

        (int256 amount0_, int256 amount1_) = _zeroForOne
            ? (int256(_amountIn), -int256(getAmountOut(_amountIn, _reserve0, _reserve1)))
            : (-int256(getAmountOut(_amountIn, _reserve1, _reserve0)), int256(_amountIn));

        address inToken = _zeroForOne ? token0 : token1;
        address outToken = _zeroForOne ? token1 : token0;
        uint256 balanceIn = IERC20(inToken).balanceOf(address(this));
        //erc20 transfer output token

        if (_zeroForOne) {
            _safeTransfer(token1, _to, uint256(-amount1_));
        } else {
            _safeTransfer(token0, _to, uint256(-amount0_));
        }

        IkSwapSwapCallback(msg.sender).kSwapCallback(amount0_, amount1_, _data);

        //verify that input token was transferred
        uint256 balanceOut = IERC20(inToken).balanceOf(address(this));

        if (balanceIn + _amountIn > balanceOut) {
            revert InsufficientInputAmount();
        }

        uint256 balance1 = IERC20(outToken).balanceOf(address(this));
        if (balanceOut > type(uint112).max || balance1 > type(uint112).max) {
            revert SwapOverflow();
        }

        //update reserves
        if (_zeroForOne) {
            reserve0 = uint112(balanceOut);
            reserve1 = uint112(balance1);
        } else {
            reserve1 = uint112(balanceOut);
            reserve0 = uint112(balance1);
        }

        emit Swap(msg.sender, amount0_, amount1_);
        return _zeroForOne ? uint256(-amount1_) : uint256(-amount0_);
    }
}
