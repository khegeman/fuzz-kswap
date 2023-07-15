from woke.testing import *
import pytest

import os    
from woke.development.core import Address

from pytypes.contracts.kSwapPool import kSwapPool, IERC20
from pytypes.contracts.kSwapRouter import kSwapRouter
from pytypes.tests.contracts.kReenter import kReenter
import string
from woke.development.primitive_types import uint

from woke.testing.core import default_chain
from woke.development.transactions import must_revert
from woke.testing.fuzzing import FuzzTest,flow,invariant
from dotenv import load_dotenv
from . import st
from math import sqrt,ceil
from typing import cast
load_dotenv()

RPC_URL=os.getenv('RPC_URL')
FORK_URL=f"{RPC_URL}@17644779" 
import random

random.seed(44)

USDC = Address("0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48")
WETH = Address("0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2")

#use balancer as a wallet to acquire real ERC20 tokens for testing 
BALANCER = Address("0xBA12222222228d8Ba445958a75a0704d566BF2C8")

PrintEnabled=True

def mint_helper(to : Address, ks : kSwapPool, amount0: uint):

    kr = kSwapRouter.deploy()


    t0 = IERC20(ks.token0())
    t1 = IERC20(ks.token1())

    amount1 = amount0
    try:
        amount1 = ks.previewMint(amount0)
    except:
        pass


    #check if we should get InsufficientLiquidityMinted
    supply = ks.totalSupply()
    (r0,r1) = ks.getReserves()
    if supply > 0:
        minAmount0 = ceil(r0/supply)
        minAmount1 = ceil(r1/supply)

        shouldInsufficientLiquidityMinted = amount0 < minAmount0 or amount1 < minAmount1
    else:
        shouldInsufficientLiquidityMinted = False
    t0.transfer(to, amount0, from_=BALANCER)
    t1.transfer(to, amount1, from_=BALANCER)

    t0.approve(kr, amount0,from_=to)
    t1.approve(kr, amount1,from_=to)
    if shouldInsufficientLiquidityMinted:
        with must_revert(kSwapPool.InsufficientLiquidityMinted):
           tx = kr.addLiquidity(ks,amount0,amount1,0,0,from_=to) 
        return None   
    else:
        return kr.addLiquidity(ks,amount0,amount1,0,0,from_=to)



class KSwapFuzzTest(FuzzTest):
    _pool: kSwapPool
    users = st.Data()
    
    @property
    def pool(self):
        return self._pool

    @st.collector()
    def pre_sequence(self) -> None:
        self._pool = kSwapPool.deploy(USDC,WETH)
        
        self.users.set(st.random_addresses(len=5)())

        self.liquidity = 0
        
        

        
    @flow()
    @st.given(to_=st.choose(users),amount0=st.random_int(min=1, max=40000000000))
    @st.print_steps(do_print=PrintEnabled)    
    def flow_mint(self,to_,amount0) -> None:

        mtx = mint_helper(to_,self.pool, amount0)
        if mtx is not None:
            (a0,a1,liquidity) = mtx.return_value

            self.liquidity += liquidity
        
        

    @flow(precondition=lambda self: cast(KSwapFuzzTest,self).pool.totalSupply() > 0)
    @st.given(to_=st.choose(users))
    @st.print_steps(do_print=PrintEnabled)      
    def flow_burn(self,to_) -> None:

        to_burn = self.pool.balanceOf(to_)
        if (to_burn > 0):

            self.pool.transfer(self.pool,to_burn,from_=to_ )
            self.pool.burn(to_,from_=to_)
            self.liquidity -= to_burn
            
    
    @flow(precondition=lambda self: cast(KSwapFuzzTest,self).pool.totalSupply() > 0)
    @st.given(to_=st.choose(users),zeroForOne=st.random_bool(true_prob=0.5), amount=st.random_int(min=1, max=40000000000))
    @st.print_steps(do_print=PrintEnabled)  
    def flow_swap(self,to_,zeroForOne,amount):
        t0 = IERC20(self.pool.token0())
        t1 = IERC20(self.pool.token1())
        if self.pool.totalSupply() > 0:
            kr = kSwapRouter.deploy()        
            if zeroForOne:
                t0.transfer(to_, amount, from_=BALANCER)        
                t0.approve(kr, amount,from_=to_)
            else:
                t1.transfer(to_, amount, from_=BALANCER)        
                t1.approve(kr, amount,from_=to_)

            tx = kr.swap(self.pool,zeroForOne,amount,from_=to_)

    #to test with re-entrancy adjust weight to 100
    @flow(weight=0,precondition=lambda self: cast(KSwapFuzzTest,self).pool.totalSupply() > 0)
    @st.given(to_=st.choose(users),zeroForOne=st.random_bool(true_prob=0.5), amount=st.random_int(min=1, max=400))
    @st.print_steps(do_print=PrintEnabled)      
    def flow_swapre(self,to_,zeroForOne,amount):
        t0 = IERC20(self.pool.token0())
        t1 = IERC20(self.pool.token1())
        if self.pool.totalSupply() > 0:
            kr = kReenter.deploy()        
            if zeroForOne:
                t0.transfer(to_, amount, from_=BALANCER)        
                t0.approve(kr, amount,from_=to_)
            else:
                t1.transfer(to_, amount, from_=BALANCER)        
                t1.approve(kr, amount,from_=to_)

            tx = kr.swap(self.pool,zeroForOne,amount,from_=to_)
    
        
    

    #Period is set to 1 to verify the invariant after every flow
    @invariant(period=1)
    def invariant_reserves(self) -> None:
        (r0,r1) = self.pool.getReserves()
        assert sqrt(r0*r1) >= self.liquidity


@default_chain.connect(
    fork=FORK_URL
)
def test_swap_fuzz():
    default_chain.set_default_accounts(default_chain.accounts[0])
    KSwapFuzzTest().run(sequences_count=1, flows_count=10)

