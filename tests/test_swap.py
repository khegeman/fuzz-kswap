

from pytypes.contracts.kSwapPool import kSwapPool, IERC20
from pytypes.contracts.kSwapRouter import kSwapRouter
from pytypes.tests.contracts.kNoRepay import kCheckNoRepay
from pytypes.tests.contracts.kReenter import kReenter
from woke.development.core import Address

from pytypes.contracts.kSwapPool import kSwapPool, IERC20
from pytypes.contracts.kSwapRouter import kSwapRouter
from pytypes.tests.contracts.kReenter import kReenter
import string
from woke.development.primitive_types import uint

from woke.testing.core import default_chain
from woke.development.transactions import must_revert


import os 
from dotenv import load_dotenv

load_dotenv()

RPC_URL=os.getenv('RPC_URL')
FORK_URL=f"{RPC_URL}@17644779" 

USDC = Address("0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48")
WETH = Address("0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2")

#use balancer as a wallet to acquire real ERC20 tokens for testing 
BALANCER = "0xBA12222222228d8Ba445958a75a0704d566BF2C8"

from . import st
def mint_helper(to, ks, amount0, amount1):

    kr = kSwapRouter.deploy()

    t0 = IERC20(ks.token0())
    t1 = IERC20(ks.token1())

    t0.transfer(to, amount0, from_=BALANCER)
    t1.transfer(to, amount1, from_=BALANCER)

    t0.approve(kr, amount0,from_=to)
    t1.approve(kr, amount1,from_=to)
    return kr.addLiquidity(ks,amount0,amount1,0,0,from_=to)


@default_chain.connect()
def test_swap_no_liquidity():
    default_chain.set_default_accounts(default_chain.accounts[0])
    ks = kSwapPool.deploy(USDC,WETH)
    act = default_chain.accounts[0]
    with must_revert():
        ks.swap(act, True,10,b"" )
    


@default_chain.connect(
        fork=FORK_URL
)
def test_mint_1to1():
    act = default_chain.accounts[0]
    default_chain.set_default_accounts(act)

    #minting returns erc20 tokens representing the position in the pool
    #basic minting tests adds tokens in the 1:1 ratio 
    ks = kSwapPool.deploy(USDC,WETH)
    amt = 1000
    mtx = mint_helper(act, ks,amt,amt)

    #verify that the proper events were emitted and that the correct number of erc20 tokens were issued

    assert mtx.events == [
                            IERC20.Transfer(act.address,ks.address,amt),
                            IERC20.Transfer(act.address,ks.address,amt),
                            IERC20.Transfer(Address(0), act.address, amt), 
                            kSwapPool.Mint(act.address, amt,amt)]
    assert amt == ks.balanceOf(act) 


@default_chain.connect(
        fork=FORK_URL
)
def test_invalid_to():
    act = default_chain.accounts[0]
    default_chain.set_default_accounts(act)

    ks = kSwapPool.deploy(USDC,WETH)
    amt = 1000
    mint_helper(act, ks,amt,amt)

    trade_size=1000000

    with must_revert(kSwapPool.InvalidTo):
        ks.swap(USDC,True, trade_size, b"" )

@default_chain.connect(
        fork=FORK_URL
)
def test_amountin_0():
    act = default_chain.accounts[0]
    default_chain.set_default_accounts(act)

    ks = kSwapPool.deploy(USDC,WETH)
    amt = 1000
    mint_helper(act, ks,amt,amt)

    with must_revert(kSwapPool.AmountIn0):
        ks.swap(USDC,True, 0, b"" )


@default_chain.connect(
        fork=FORK_URL
)
def test_insufficient_burn():
    act = default_chain.accounts[0]
    default_chain.set_default_accounts(act)

    #minting returns erc20 tokens representing the position in the pool
    #basic minting tests adds tokens in the 1:1 ratio 
    ks = kSwapPool.deploy(USDC,WETH)

    #total supply is 0, can't burn
    with must_revert(kSwapPool.InsufficientLiquidityBurned):
        ks.burn(act)

    amt = 1000
    mtx = mint_helper(act, ks,amt,amt*2)

    #we minted, but didn't transfer lp tokens
    with must_revert(kSwapPool.InsufficientLiquidityBurned):
        ks.burn(act)

@default_chain.connect(
        fork=FORK_URL
)
def test_mint_1to2():
    act = default_chain.accounts[0]
    default_chain.set_default_accounts(act)

    #minting returns erc20 tokens representing the position in the pool
    #basic minting tests adds tokens in the 1:1 ratio 
    ks = kSwapPool.deploy(USDC,WETH)
    amt = 1000
    mtx = mint_helper(act, ks,amt,amt*2)

    #verify that the proper events were emitted and that the correct number of erc20 tokens were issued

    liquidity= 1414
    assert mtx.events == [IERC20.Transfer(act.address,ks.address,amt),
                          IERC20.Transfer(act.address,ks.address,amt*2),
                          IERC20.Transfer(Address(0), act.address, liquidity), 
                          kSwapPool.Mint(act.address, amt,amt*2)]
    assert liquidity == ks.balanceOf(act) 

@default_chain.connect(
        fork=FORK_URL
)
def test_burn():
    act = default_chain.accounts[0]
    default_chain.set_default_accounts(act)

    #minting returns erc20 tokens representing the position in the pool
    #basic minting tests adds tokens in the 1:1 ratio 
    ks = kSwapPool.deploy(USDC,WETH)
    amt = 1000
    mtx = mint_helper(act, ks,amt,amt*2)

    #verify that the proper events were emitted and that the correct number of erc20 tokens were issued

    liquidity = ks.balanceOf(act)
    #to burn we have to transfer the tokens to the contract
    ks.transfer(ks, liquidity,from_=act)
    btx = ks.burn(act)

    assert btx.events == [IERC20.Transfer(ks.address, Address(0), liquidity),IERC20.Transfer(ks.address, act.address, amt),IERC20.Transfer(ks.address, act.address, 2*amt),kSwapPool.Burn(act.address,amt,2*amt,act.address)]

    assert amt == IERC20(USDC).balanceOf(act)
    assert 2*amt == IERC20(WETH).balanceOf(act)

@default_chain.connect(
        fork=FORK_URL
)
def test_swap():
    default_chain.set_default_accounts(default_chain.accounts[0])

    act = default_chain.accounts[0]


    ks = kSwapPool.deploy(USDC,WETH)

    usdc = IERC20(USDC)
    weth = IERC20(WETH)
    amt = 100000000000
    mtx = mint_helper(act, ks, amt,amt )

    kr = kSwapRouter.deploy()

    trade_size=1000000
    usdc.transfer(act, trade_size, from_=BALANCER)    
    usdc.approve(kr, trade_size,from_=act)

    tx = kr.swap(ks, True, trade_size)
    
    #swap should add the input amount to the balance of usdc
    assert usdc.balanceOf(ks.address) == amt + trade_size
    #swap should subtract the input amount to the balance of usdc
    assert weth.balanceOf(ks.address) == amt - tx.return_value
    assert weth.balanceOf(act) == tx.return_value

    weth.approve(kr, tx.return_value,from_=act)
    tx = kr.swap(ks, False, tx.return_value)
    liquidity = ks.balanceOf(act)
    ks.transfer(ks, liquidity,from_=act)
    btx = ks.burn(act)

    #after we burn, everything should be back in our account
    assert usdc.balanceOf(act) == amt + trade_size
    assert weth.balanceOf(act) == amt      

@default_chain.connect(
        fork=FORK_URL
)
def test_iia():
    default_chain.set_default_accounts(default_chain.accounts[0])

    act = default_chain.accounts[0]


    ks = kSwapPool.deploy(USDC,WETH)

    usdc = IERC20(USDC)
    weth = IERC20(WETH)
    amt = 100000000000
    mtx = mint_helper(act, ks, amt,amt )

    kr = kCheckNoRepay.deploy()

    trade_size=1000000
    usdc.transfer(act, trade_size, from_=BALANCER)    
    usdc.approve(kr, trade_size,from_=act)

    with must_revert(kSwapPool.InsufficientInputAmount):
        tx = kr.swap(ks, True, trade_size)
 
@default_chain.connect(
        fork=FORK_URL
)
def test_reenter():
    default_chain.set_default_accounts(default_chain.accounts[0])
    default_chain.tx_callback = lambda tx: print(tx.console_logs)
    act = default_chain.accounts[0]


    ks = kSwapPool.deploy(USDC,WETH)

    usdc = IERC20(USDC)
    weth = IERC20(WETH)
    amt = 100000000000
    mtx = mint_helper(act, ks, amt,amt )

    kr = kReenter.deploy()

    trade_size=1000000
    usdc.transfer(act, trade_size*2, from_=BALANCER)    
    print(act.address)
    usdc.approve(kr, trade_size*2,from_=act)

    tx = kr.swap(ks, True, trade_size)

    print(tx.events)
    


    #after we burn, everything should be back in our account
    print(usdc.balanceOf(ks.address),weth.balanceOf(ks.address))
    #assert weth.balanceOf(kr.address)