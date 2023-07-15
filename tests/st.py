#various helper decorators developed for fuzzing with woke


import woke.testing.fuzzing
import functools
import random

MAX_UINT=2**256-1

def random_ints(len, min_val=0, max_val=MAX_UINT):
    def f():
        return [woke.testing.fuzzing.random_int(min_val, max_val) for i in range(0,len) ]
    return f


def random_addresses(len):
    def f():
        return [woke.testing.fuzzing.random_address() for i in range(0,len) ]
    return f

def random_int(min=0,max=MAX_UINT,**kwargs):
    def f():
        return woke.testing.fuzzing.random_int(min=min,max=max,**kwargs)
    return f

def choose(values):
    def f():        
        return random.choice(values.get())
    return f
    
def random_bool(true_prob):
    def f():
        return woke.testing.fuzzing.random_bool(true_prob=true_prob)
    return f

def choose_n(values, min_k, max_k):
    def f():
        
        return random.choices(values.get(),k=woke.testing.fuzzing.random_int(min_k,max_k))
    return f
    
def random_bytes(min, max):
    def f():
        return woke.testing.fuzzing.random_bytes(min,max)
    return f


def given(*args, **akwargs):
    def decorator(fn):
        @functools.wraps(fn)
        def wrapped(*args, **kwargs):
            params = {k : v() if callable(v) else v for k,v in akwargs.items()}      

            collector = getattr(args[0], '_collector', None)
            if collector is not None:
                collector.collect(args[0], fn,**params)
            return fn(args[0],**params)
        return wrapped
    return decorator

from collections import defaultdict
from collections import namedtuple

def getAddress(u):
    addr = getattr(u, 'address', None)
    if addr is not None:
        return addr
    
    return u


FlowMetaData = namedtuple("FlowMetaData", "name params") 

class DictCollector():
       
    def __init__(self, ):
        self._values = defaultdict(lambda: defaultdict(FlowMetaData))

    def __repr__(self):
        return self._values.__repr__()

    @property
    def values(self):
        return self._values                

    def collect(self,fuzz, fn, **kwargs):
        self._values[fuzz._sequence_num][fuzz._flow_num]=FlowMetaData(fn.__name__, kwargs)

def collector(*args, **kwargs):
    def decorator(fn):
        @functools.wraps(fn)        
        def wrapped(*args, **kwargs):   
            args[0]._collector = DictCollector()
            return fn(*args,**kwargs)
        return wrapped
    return decorator

class Data():

    values = [] 

    def set(self, v):
        self.values = v
    def get(self):
        return self.values

from collections import defaultdict,namedtuple

TX = namedtuple("TX", "events") 
    
def invoker(s_impl, p_impl):


    def invoke(fname,expected_execptions=[], **kwargs): 
        py_revert = False 
        sol_revert = False
        import inspect 
  
        def scall(object,name,**kwargs):
            fn = getattr(object,name )      
            sig = inspect.signature(fn)
            arglist = {arg : kwargs[arg]  for arg in sig.parameters if arg in kwargs}
            return fn(**arglist)

        stx = None
        ptx = None
        try:
            fn = getattr(p_impl, fname)            
            sig = inspect.signature(fn)
            arglist = {arg : kwargs[arg] for arg in sig.parameters }
   
            ptx = fn(**arglist)
        except Exception as e:
            print(e)
            py_revert = True
        
        try:               
            stx = scall(s_impl, fname,**kwargs)      
        except Exception as e:
            print(fname, "error", e,any([ isinstance(e,ex) for ex in expected_execptions]))
            if any([isinstance(e,ex) for ex in expected_execptions]):
                sol_revert = True
            else:
                raise e
            
        assert py_revert == sol_revert , {"invoke of {} failed assertion check".format(fname)}       
        
        
        if isinstance(ptx, TX):
            assert stx is not None
            assert ptx.events == stx.events , {"invoke of {} failed event match check".format(fname)}     
        return stx
    return invoke


### Add this dectorator to print each flow in a sequence
def print_steps(do_print=False,*args, **kwargs):
    def decorator(fn):
        @functools.wraps(fn)        
        def wrapped(*args, **kwargs):   
            if do_print:
                print("seq:",args[0]._sequence_num,"flow:",args[0]._flow_num, "flow name:",fn.__name__,"flow parameters:",kwargs)
            return fn(*args,**kwargs)
        return wrapped
    return decorator