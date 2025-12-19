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

local AptInt = require(script.Parent)

type AptInt = AptInt.AptInt

export type Extensions = {
	read Abs: (n: AptInt, inPlace: boolean) -> AptInt,
	read IsEven: (n: AptInt) -> boolean,
}

AptInt.Extend(function(tbl: typeof(AptInt) | any)
	function tbl:Abs(inPlace: boolean): AptInt
		if inPlace then
			self.signum = -self.signum
			return self
		end
		
		local result = AptInt.clone(self)
		result.signum = -result.signum
		return result
	end
	
	function tbl:IsEven(): boolean
		return (self :: AptInt).limbs[1] % 2 == 0
	end
	
	tbl.zero = AptInt.new()
	tbl.one = AptInt.new({1})
end)

return {}
