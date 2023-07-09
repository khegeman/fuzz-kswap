

#test calcs for exchange 

def GetAmountOut(reserveIn, reserveOut, amountIn):
        numerator = amountIn * reserveOut
        denominator = reserveIn + amountIn
                            
        ao = numerator / denominator
        return (ao, reserveIn + amountIn, reserveOut-ao)


(ao,r0,r1) = GetAmountOut(1000,1000,100)

print(ao,r0,r1)

(a1,r2,r3) = GetAmountOut(r1,r0,ao)

print(ao,a1,r2,r3)