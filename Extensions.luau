--!optimize 2
--!native
--!strict

-- ===============================================================
--[[ 
-- AptInt.luau // fosterchild 2025 - Luau implementation of BigInteger, with added typechecking.
-- Licensed under The Unlicense.

-- Documentation and source can be found at: https://github.com/fosterchild1/AptInt.luau/tree/main
--]]
-- ===============================================================

local AptInt = require(script.Parent)

type AptInt = AptInt.AptInt

export type Extensions = {
	read zero: AptInt,
	read one: AptInt,
	
	read Abs: (n: AptInt, inPlace: boolean) -> AptInt,
	read IsEven: (n: AptInt) -> boolean,
	read Min: (...AptInt) -> boolean,
	read Max: (...AptInt) -> boolean,
	read Clamp: (n: AptInt, min: AptInt, max: AptInt) -> AptInt,
	read ModPow: (n: AptInt, mod: AptInt, exp: AptInt) -> AptInt,
}

export type ExtendedApt = AptInt & Extensions

local bband: (number, number) -> number = bit32.band
local brshift: (number, number) -> number = bit32.rshift

local abs: (number) -> number = math.abs

local AP_TW0: AptInt = AptInt.new({2})
local AP_ONE: AptInt = AptInt.new({1})

AptInt.Extend(function(tbl: typeof(AptInt) | any)
	-->Returns a new AptInt equal to <code>|n|</code>.
	function tbl:Abs(inPlace: boolean): AptInt
		if inPlace then
			self.signum = abs(self.signum)
			return self
		end
		
		local result = AptInt.clone(self)
		result.signum = abs(result.signum)
		return result
	end
	
	-- Returns <code>true</code> if <code>n</code> is even.
	function tbl:IsEven(): boolean
		return (self :: AptInt).limbs[1] % 2 == 0
	end
	
	-- Returns the minimum value among the AptInts passed into the function.
	function tbl:Min(...: AptInt): AptInt
		local ints: {AptInt} = {...}
		local lowest: AptInt = ints[1]
		
		for i: number = 2, #ints do
			local num: AptInt = ints[i]
			
			if num:LowerThanRaw(lowest) then
				lowest = num
			end
		end
		
		return lowest:clone()
	end
	
	-- Returns the maximum value among the AptInts passed into the function.
	function tbl:Max(...: AptInt): AptInt
		local ints: {AptInt} = {...}
		local highest: AptInt = ints[1]

		for i: number = 2, #ints do
			local num: AptInt = ints[i]

			if highest:LowerThanRaw(num) then
				highest = num
			end
		end

		return highest:clone()
	end
	
	-- Returns an AptInt between <code>min</code> and <code>max</code>, inclusive.
	function tbl:Clamp(min: AptInt, max: AptInt): AptInt
		if self:LowerThanRaw(min) then
			return min:clone()
		elseif max:LowerThanRaw(self) then
			return max:clone()
		end
		
		return self:clone()
	end
	
	-- Returns the value of <code>a<sup>e</sup> % m</code>.
	function tbl:ModPow(mod: AptInt, exp: AptInt): AptInt
		-- https://en.wikipedia.org/wiki/Modular_exponentiation#Right-to-left_binary_method
		local a: AptInt = self:ModRaw(mod)
		
		local result: AptInt = AP_ONE:clone()
		
		--> single limb optimization
		if #exp.limbs == 1 then
			local e: number = exp.limbs[1]
			while e ~= 0 do
				if bband(e, 1) == 1 then
					result = result:MultiplyRaw(a):ModRaw(mod)
				end
				
				e = brshift(e, 1)
				a = a:MultiplyRaw(a):ModRaw(mod)
			end
			
			return result
		end
		
		while exp.signum ~= 0 do
			if bband(exp.limbs[1], 1) == 1 then
				result = result:MultiplyRaw(a):ModRaw(mod)
			end
			
			a = a:MultiplyRaw(a):ModRaw(mod)
			exp = exp:DivideRaw(AP_TW0)
		end

		return result
	end
	
	tbl.zero = AptInt.new()
	tbl.one = AptInt.new({1})
end)

return {}
