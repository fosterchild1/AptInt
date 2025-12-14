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
	read Abs: (n: BigInteger) -> BigInteger,
	read AbsInPlace: (n: BigInteger) -> BigInteger
}

BigInteger.Extend(function(tbl: typeof(BigInteger) | any)
	function tbl:Abs(): BigInteger
		local result = BigInteger.new(self)
		result.signum = (result.signum > -1 and result.signum or 1)

		return result
	end

	function tbl:AbsInPlace(): BigInteger
		self.signum = (self.signum > -1 and self.signum or 1)

		return self
	end
	
	function tbl:IsEven(): boolean
		return (self :: BigInteger).digits[1] % 2 == 0
	end
	
	function tbl:IsOdd(): boolean
		return (self :: BigInteger).digits[1] % 2 ~= 0
	end
end)

return {}
