--!optimize 2
--!native
--!strict

-- ===============================================================
--[[ 
-- BigInteger.luau // fosterchild 2025 - Luau implementation of Java's BigInteger, with added typechecking.
-- Licensed under The Unlicense.

-- Documentation and source can be found at: https://github.com/fosterchild1/BigInteger.luau/tree/main
--]]
-- ===============================================================

-- INSPO: https://github.com/openjdk/jdk/blob/master/src/java.base/share/classes/java/math/BigInteger.java

local BigInteger = require(script.Parent)

type BigInteger = BigInteger.BigInteger

export type Extensions = {
	read Abs: (n: BigInteger, inPlace: boolean) -> BigInteger,
	read IsEven: (n: BigInteger) -> boolean,
}

BigInteger.Extend(function(tbl: typeof(BigInteger) | any)
	function tbl:Abs(inPlace: boolean): BigInteger
		if inPlace then
			self.signum = -self.signum
			return self
		end
		
		local result = BigInteger.clone(self)
		result.signum = -result.signum
		return result
	end
	
	function tbl:IsEven(): boolean
		return (self :: BigInteger).limbs[1] % 2 == 0
	end
	
	tbl.zero = BigInteger.new()
	tbl.one = BigInteger.new({1})
end)

return {}
