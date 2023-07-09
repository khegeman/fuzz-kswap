from woke.testing import *
import pytest

import os    
from woke.testing import Address
from pytypes.contracts.kSwapPool import kSwapPool, IERC20
from pytypes.contracts.kSwapRouter import kSwapRouter

import string

from woke.testing.fuzzing import *
from dotenv import load_dotenv
from . import st


load_dotenv()

RPC_URL=os.getenv('RPC_URL')
FORK_URL=f"{RPC_URL}@17644779" 




USDC = "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48"
WETH = "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2"

#use balancer as a wallet to acquire real ERC20 tokens for testing 
BALANCER = "0xBA12222222228d8Ba445958a75a0704d566BF2C8"


def mint_helper(to, ks, amount0, amount1):

    t0 = IERC20(ks.token0())
    t1 = IERC20(ks.token1())

    t0.transfer(ks, amount0, from_=BALANCER)
    t1.transfer(ks, amount1, from_=BALANCER)

    return ks.mint(from_=to)


class KSwapFuzzTest(FuzzTest):
    pool: kSwapPool
    users = st.Data()
    


    @st.collector()
    def pre_sequence(self) -> None:
        self.pool = kSwapPool.deploy(USDC,WETH)
        
        self.users.set(st.random_addresses(len=2)())

        self.amount0_minted = 0
        self.amount1_minted = 0

        
    @flow()
    @st.given(to_=st.choose(users),amount0=st.random_int(max=400),amount1=st.random_int(max=400))
    def flow_mint(self,to_,amount0,amount1) -> None:

        mint_helper(to_,self.pool, amount0,amount1)

        self.amount0_minted += amount0
        self.amount1_minted += amount1
     

    @invariant(period=1)
    def invariant_reserves(self) -> None:
        (r0,r1) = self.pool.getReserves()
        assert r0 == self.amount0_minted
        assert r1 == self.amount1_minted

@default_chain.connect(
    fork=FORK_URL
)
def test_swap_fuzz():
    default_chain.set_default_accounts(default_chain.accounts[0])
    KSwapFuzzTest().run(sequences_count=1, flows_count=1)

