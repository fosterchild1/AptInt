--!optimize 2
--!native
--!strict

-- ===============================================================
--[[ 
-- AptInt.luau // fosterchild 2025 - Luau implementation of BigInteger, with added typechecking.
-- Licensed under The Unlicense.

-- Documentation and source can be found at: https://github.com/fosterchild1/AptInt/
--]]
-- ===============================================================

local AptInt = {}
AptInt.__index = AptInt

local Add = require("./Modules/Add")
local Sub = require("./Modules/Sub")
local Mul = require("./Modules/Mul")
local Div = require("./Modules/Div")
local Sqrt = require("./Modules/Sqrt")
local Cmp = require("./Modules/Cmp")
local Type = require("./Type")

export type AptInt = Type.AptInt
export type ValidMetamethodArgument = Type.ValidMetamethodArgument
export type ValidConstructor = Type.ValidConstructor

-- ================================
--> OPTIMIAZTION FUNCTION CONSTANTS
-- ================================

local log10: (number) -> number = math.log10
local log: (number, number) -> number = math.log
local floor: (number) -> number = math.floor
local ceil: (number) -> number = math.ceil
local max: (number, number) -> number = math.max
local min: (number, number) -> number = math.min
local abs: (number) -> number = math.abs
local sign: (number) -> number = math.sign

-- the types here may be off, but native optimizes them more than their actual types
local tcreate: <V>(number, V) -> {V} = table.create
local tinsert: <V>({V}, V) -> () = table.insert
local tremove: ({number}, number) -> number = table.remove
local tconcat: <V>({V}, string?, number?, number?) -> string = table.concat
local tmove: ({number}, number, number, number, {number}) -> {number} = table.move
local tclone: ({number}) -> {number} = table.clone

local sformat: (string, ...unknown) -> string = string.format

-- =================
--> NORMAL CONSTANTS
-- =================

local BURNIKEL_THRESHOLD: number = 280
local MIN_BURNIKEL_OFFSET: number = 40

local BASE_POW: number = 24 -- MUST SATISFY: 2^(BASE_POW*2) < 2^53, because of multiplyraw and divideraw
local BASE: number = 2^24 -- we use base 2^24 or else multiplication goes over 2^53
local BASE_MASK: number = 0xFFFFFF -- BASE - 1

local RADIX_LEN_CONST: number = 7.224719895935548 -- BASE_POW * log10(2)
local RADIX_CHUNK_SIZE: number = 10^8

local AP_NEG_ONE: AptInt, AP_ONE: AptInt, AP_THREE: AptInt

--> CONSTRUCTOR
local typeConstructors: {[string]: (any) -> ({number}, number)} = {
	["string"] = function(str: string): ({number}, number)
		local isNegative: boolean = str:sub(1, 1) == "-"
		if isNegative then
			str = str:sub(2, #str)
		end
		
		--> TODO: we could probably use algoritm 1.25 FastIntegerInput
		--> convert from decimal to base 2^24
		local out: {number} = {}
		local chunks: {number} = {}
		
		for i: number = #str, 1, -8 do
			local start: number = max(i - 7, 1)
			tinsert(chunks, tonumber(str:sub(start, i)) or 0)
		end

		while #chunks > 0 do
			local carry: number = 0
			for i: number = #chunks, 1, -1 do
				local val: number = chunks[i] + carry * RADIX_CHUNK_SIZE

				chunks[i] = val // BASE
				carry = val % BASE
			end

			tinsert(out, carry)
			
			--> stripleadingzeros
			while true do 
				local len: number = #chunks 
				if len == 0 or chunks[len] ~= 0 then break end 

				chunks[len] = nil 
			end
		end

		return out, (isNegative and -1 or 1)
	end,

	["number"] = function(num: number): ({number}, number)
		if num == 0 then
			return {0}, 0
		elseif num == -1 then
			return {1}, -1
		end

		local actualSign: number = sign(num)
		num = abs(num)

		local arr: {number} = {}
		while num > 0 do
			tinsert(arr, floor(num % BASE))
			num //= BASE
		end

		return arr, actualSign
	end,

	["table"] = function(tbl: {any}): ({number}, number)	
		local first: number = tbl[1]
		if not first then
			return {0}, 0
		end

		return tbl, 1
	end,

	["nil"] = function(_: nil): ({number}, number)
		return {0}, 0
	end,
}

-- ==================
--> PRIVATE FUNCTIONS
-- ==================

local function ArgumentToAptInt(num: ValidMetamethodArgument?, errContext: string): AptInt
	local bigint: AptInt;

	--> make sure toAdd is correct
	if getmetatable(num :: AptInt?) == AptInt then
		bigint = num :: AptInt
	else
		local numType: string = typeof(num)

		assert(
			typeConstructors[numType] ~= nil,
			`attempt to perform arithmetic ({errContext}) on AptInt and {numType}`
		)

		bigint = AptInt.new(num :: ValidConstructor)
	end

	return bigint
end

local function Div2InPlace(n: AptInt)
	local limbs: {number} = n.limbs
	local carry: number = 0

	for i: number = #limbs, 1, -1 do
		local x: number = limbs[i] + carry * BASE

		carry = x % 2
		limbs[i] = x // 2
	end

	StripLeadingZeros(n)
end

local function NegateRef(n: AptInt): AptInt
	return setmetatable({
		limbs = n.limbs,
		signum = -n.signum,
	}, AptInt) :: AptInt
end

-- =======================
-- ALL SORTS OF ALGORITHMS
-- =======================

--> divsion stuff
local function CorrectRemainder(self: AptInt, divisor: AptInt, remainder: AptInt): AptInt
	local selfSign: number, divSign: number = self.signum, divisor.signum
	local sameSign: boolean = selfSign == divSign

	if sameSign and divSign == -1 then
		remainder.signum = -1
		return remainder
	elseif selfSign == 1 and divSign == -1 and remainder.signum ~= 0 then
		return divisor:AddRaw(remainder)
	elseif not sameSign and remainder.signum ~= 0 then -- selfsign -1, divsign 1
		remainder.signum = 1
		return divisor:SubtractRaw(remainder)
	end

	return remainder
end


-- ====================
--> METATABLE FUNCTIONS
-- ====================

-- Returns a new AptInt from the given argument.
function AptInt.new(num: ValidConstructor): AptInt
	local limbs: {number}, signum: number = typeConstructors[typeof(num)](num)

	return setmetatable({
		limbs = limbs,
		signum = signum
	}, AptInt) :: AptInt
end

--> this is ugly. needed constants in MulToom3 and division
AP_NEG_ONE, AP_ONE, AP_THREE = AptInt.new(-1), AptInt.new({1}),  AptInt.new({3})

-- Returns a copy of the AptInt.
function AptInt:clone(): AptInt
	return setmetatable({
		limbs = tclone(self.limbs),
		signum = self.signum
	}, AptInt) :: AptInt
end

-- Returns an AptInt with its sign flipped.
function AptInt:Negate(inPlace: boolean): AptInt
	if inPlace then
		self.signum = -self.signum
		return self :: AptInt
	end

	local result: AptInt = self:clone()
	result.signum = -result.signum

	return result
end

-- =====================
--> ARITHMETIC FUNCTIONS
-- =====================

-- Returns an AptInt equal to <code>a + b</code>.
function AptInt:AddRaw(term: AptInt, inPlace: boolean?): AptInt
	local selfSign: number, termSign: number = self.signum, term.signum

	--> CASES
	if termSign == 0 then
		return (inPlace and self or self:clone())
	elseif selfSign == 0 then
		local clone: AptInt = term:clone()
		if inPlace then self = clone end

		return clone
	elseif selfSign == -1 and termSign == 1 then -- -a+b = b+(-a) = b-a
		return (NegateRef(self):SubtractRaw(term, inPlace)):Negate(true)
	elseif selfSign ~= termSign then -- +a+(-b)=a-b
		return self:SubtractRaw(NegateRef(term), inPlace)
	end
	
	local result: {number} = Add.AddLimbs(self.limbs, term.limbs, inPlace)
	return (inPlace and self or AptInt.new(result))
end

-- Returns an AptInt equal to <code>a - b</code>.
function AptInt:SubtractRaw(term: AptInt, inPlace: boolean?): AptInt
	local selfSign: number, termSign: number = self.signum, term.signum

	--> CASES
	if termSign == 0 then -- b - 0 = 0
		return (inPlace and self or self:clone())
	elseif selfSign == 0 then -- 0 - b = -b
		local negate: AptInt = term:Negate()
		if inPlace then self = negate end

		return negate
	elseif termSign == -1 and selfSign == 1 then -- a-(-b) = a+b
		return NegateRef(term):AddRaw(self)
	elseif termSign == -1 and selfSign == -1 then -- (-a-(-b)) = b-a
		return (NegateRef(self):SubtractRaw(NegateRef(term), inPlace)):Negate(true)
	end

	if self:LowerThanRaw(term) then
		return term:SubtractRaw(self):Negate(true)
	end
	
	local result: {number} = Sub.SubLimbs(self.limbs, term.limbs, inPlace)
	return (inPlace and self or AptInt.new(result))
end

-- Returns an AptInt equal to <code>a * b</code>.
function AptInt:MultiplyRaw(factor: AptInt, i: boolean?): AptInt
	local selfSign: number, factorSign: number = self.signum, factor.signum

	--> CASES
	if selfSign == 0 or factorSign == 0 then
		return AptInt.new()
	end
	
	local factorLimbs: {number} = factor.limbs
	
	--> single limb multiplication
	local result: {number}
	if #factorLimbs == 1 then
		result = Mul.MulByInt(self.limbs, factorLimbs[1])
	else
		result = Mul.MulLimbs(self.limbs, factorLimbs)
	end
	
	local metatblResult: AptInt = AptInt.new(result)
	metatblResult.signum = selfSign * factorSign
	return metatblResult
end

-- Returns the quotient and remainder of a / b.
function AptInt:DivideRaw(divisor: AptInt): (AptInt, AptInt)
	local divSign: number, selfSign: number = divisor.signum, self.signum
	local sameSign: boolean = divSign == selfSign

	local U: {number}, V: {number} = self.limbs, divisor.limbs
	
	--> CASES
	if divSign == 0 or selfSign == 0 then -- dividing by 0
		return AptInt.new(), AptInt.new()
	elseif Cmp.LowerThan(U, V) then
		if selfSign == 1 and divSign == -1 then
			return AP_NEG_ONE:clone(), divisor:AddRaw(self)
		elseif selfSign == -1 and divSign == 1 then
			return AP_NEG_ONE:clone(), divisor:SubtractRaw(NegateRef(self))
		elseif sameSign and divSign == -1 then
			return AptInt.new(), (self :: AptInt):clone()
		end

		return AptInt.new(), (self :: AptInt):clone()
	elseif Cmp.Equals(U, V) then -- -x/x = -1
		local div = AP_ONE:clone()
		div.signum = selfSign / divSign

		return div, AptInt.new()
	end

	
	local quotientLimbs: {number}, remLimbs: {number}
	
	if #V == 1 then -- single limb division
		quotientLimbs, remLimbs = Div.DivByInt(U, V[1])
	else
		quotientLimbs, remLimbs = Div.DivLimbs(U, V)
	end
	
	local quotient: AptInt, remainder: AptInt = AptInt.new(quotientLimbs), AptInt.new(remLimbs)
	
	remainder = CorrectRemainder(self, divisor, remainder)
	quotient.signum = selfSign / divSign
	return quotient, remainder
end

-- Returns a new AptInt equal to <code>a % b</code>.
function AptInt:ModRaw(div: AptInt): AptInt
	local divLimbs: {number}, selfLimbs: {number} = div.limbs, self.limbs

	local selfSign: number, divSign: number = self.signum, div.signum

	local divFirst: number = divLimbs[1] * divSign
	local selfFirst: number = selfLimbs[1] * selfSign

	--> CASES
	if divSign == 0 or (#divLimbs == 1 and abs(divFirst) == 1) then
		return AptInt.new()
	elseif #selfLimbs == 1 and #divLimbs == 1 then
		return AptInt.new(selfFirst % divFirst)
	end

	local _: AptInt, r: AptInt = self:DivideRaw(div)
	return r
end

-- Returns a new AptInt equal to <code>a ^ b</code>.
function AptInt:PowRaw(pow: AptInt)
	local selfSign: number, powSign: number = self.signum, pow.signum
	local selfLimbs: {number}, powLimbs: {number} = self.limbs, pow.limbs
	--> CASES
	if powSign == 0 then
		return AP_ONE:clone()
	elseif selfSign == 0 or powSign == -1 then
		return AptInt.new()
	end

	if #powLimbs == 1 and powLimbs[1] == 1 then
		return self:clone()
	elseif #selfLimbs == 1 and selfLimbs[1] == 1 then
		return AP_ONE:clone()
	end

	local result: AptInt = AP_ONE:clone()
	local selfClone: AptInt = self:clone()

	--> single-limb exponentiation
	if #powLimbs == 1 then
		local n: number = powLimbs[1]
		while n > 0 do
			if n % 2 == 1 then
				result = selfClone:MultiplyRaw(result)
			end

			selfClone = selfClone:MultiplyRaw(selfClone)
			n //= 2
		end

		return result
	end

	--> exponentiation by squaring
	local powClone: AptInt = pow:clone()

	while powClone.signum == 1 do
		if powClone.limbs[1] % 2 == 1 then
			result = selfClone:MultiplyRaw(result)
		end

		selfClone = selfClone:MultiplyRaw(selfClone)
		Div2InPlace(powClone)
	end

	return result
end

-- Returns a new AptInt equal to <code>sqrt(n)</code>.
function AptInt:sqrt(): AptInt
	--> we compute the isqrt via Newton-Heron iteration for small numbers
	--> for big numbers, we use karatsuba square root algorithm

	if self.signum ~= 1 then
		return AptInt.new()
	end
	
	return AptInt.new(Sqrt.ISqrtLimbs(self.limbs))
end

-- ==================
--> QoL FUNCTIONS
-- ==================

-- Returns a new string representation of an AptInt
function AptInt:ToString(): string
	if self.signum == 0 then
		return "0"
	end

	--> we convert from base 2^k to base 10 in chunks of 8 digits
	--> 8 = max {k | 2^24 * 10^k < 2^53}
	local limbs: {number} = self.limbs
	local clone: {number} = tclone(limbs)

	local chunkAmount: number = ceil(#clone * log10(BASE) / floor(log10(RADIX_CHUNK_SIZE)))
	local chunks: {string} = tcreate(chunkAmount, "")

	local chunkIdx: number = chunkAmount
	while #clone > 0 do
		local carry: number = 0
		for i: number = #clone, 1, -1 do
			local val: number = clone[i] + carry * BASE

			carry = val % RADIX_CHUNK_SIZE
			clone[i] = val // RADIX_CHUNK_SIZE
		end

		--> we write in reverse order
		chunks[chunkIdx] = sformat("%08d", carry)
		chunkIdx -= 1

		-- stripleadingzeros 
		while true do 
			local len: number = #clone 
			if len == 0 or clone[len] ~= 0 then break end 

			clone[len] = nil 
		end
	end

	local str: string = tconcat(chunks):gsub("^0+", "") -- removes leading zeros, fast
	return self.signum == -1 and `-{str}` or str
end


-- Returns a double equal to <code>tonumber(x)</code>
function AptInt:ToNumber(): number
	return tonumber(self:ToString()) :: number
end

-- ==================
--> COMPARISON FUNCTIONS
-- ==================

-- Returns true if <code>self == num</code>.
function AptInt:EqualsRaw(num: AptInt): boolean
	if self.signum ~= num.signum then
		return false
	end

	return Cmp.Equals(self.limbs, num.limbs)
end

-- Returns true if <code>self < num</code>.
function AptInt:LowerThanRaw(num: AptInt): boolean
	local selfSign: number, numSign: number = self.signum, num.signum

	--> check sign
	if selfSign < numSign then
		return true
	end

	local bothNegative: boolean = (selfSign == numSign and selfSign == -1)
	if bothNegative then
		return Cmp.LowerThan(num.limbs, self.limbs)
	end

	return Cmp.LowerThan(self.limbs, num.limbs)
end

-- Returns true if <code>self <= num</code>.
function AptInt:LowerOrEqualToRaw(num: AptInt): boolean
	local selfSign: number, numSign: number = self.signum, num.signum
	local selfLen: number, numLen: number = #self.limbs, #num.limbs

	--> check sign
	if selfSign <= numSign then
		return true
	end

	local bothNegative: boolean = (selfSign == numSign and selfSign == -1)
	if bothNegative then
		return Cmp.LowerOrEqualTo(num.limbs, self.limbs)
	end
	
	return Cmp.LowerOrEqualTo(self.limbs, num.limbs)
end

-- ==================
--> OTHER FUNCTIONS
-- ==================

-- Returns a new AptInt equal to <code>n * BASE<sup>n</sup></code>
function AptInt:LeftShift(n: number): AptInt
	-- this is the fastest way to leftshift
	return AptInt.new(tmove(self.limbs, 1, #self.limbs, n+1, tcreate(n, 0)))
end

-- Returns a new AptInt equal to <code>n // 10<sup>(BASE * amount)</sup></code>
function AptInt:RightShift(n: number): AptInt
	local result: AptInt = self:clone()

	local tbl: {number} = result.limbs

	for i: number = 1, n do
		tremove(tbl, 1)
	end

	return result
end

-- ============
--> METAMETHODS
-- ============

AptInt.__unm = function(num: AptInt): AptInt
	return num:Negate()
end

AptInt.__add = function(a: ValidMetamethodArgument, b: ValidMetamethodArgument): AptInt
	local term1: AptInt = ArgumentToAptInt(a, "add")
	local term2: AptInt = ArgumentToAptInt(b, "add")

	return term1:AddRaw(term2)
end

AptInt.__sub = function(a: ValidMetamethodArgument, b: ValidMetamethodArgument): AptInt
	local term1: AptInt = ArgumentToAptInt(a, "sub")
	local term2: AptInt = ArgumentToAptInt(b, "sub")

	return term1:SubtractRaw(term2)
end

AptInt.__mul = function(a: ValidMetamethodArgument, b: ValidMetamethodArgument): AptInt
	local term1: AptInt = ArgumentToAptInt(a, "mul")
	local term2: AptInt = ArgumentToAptInt(b, "mul")

	return term1:MultiplyRaw(term2)
end

local function divMeta(a: ValidMetamethodArgument, b: ValidMetamethodArgument): AptInt
	local term1: AptInt = ArgumentToAptInt(a, "div")
	local term2: AptInt = ArgumentToAptInt(b, "div")

	local quotient: AptInt, _: AptInt = term1:DivideRaw(term2)
	return quotient
end
AptInt.__div, AptInt.__idiv = divMeta, divMeta

AptInt.__mod = function(a: ValidMetamethodArgument, b: ValidMetamethodArgument): AptInt
	local term1: AptInt = ArgumentToAptInt(a, "mod")
	local term2: AptInt = ArgumentToAptInt(b, "mod")

	return term1:ModRaw(term2)
end

AptInt.__pow = function(a: ValidMetamethodArgument, b: ValidMetamethodArgument): AptInt
	local term1: AptInt = ArgumentToAptInt(a, "pow")
	local term2: AptInt = ArgumentToAptInt(b, "pow")

	return term1:PowRaw(term2)
end

AptInt.__eq = function(a: ValidMetamethodArgument, b: ValidMetamethodArgument): boolean
	local term1: AptInt = ArgumentToAptInt(a, "compare")
	local term2: AptInt = ArgumentToAptInt(b, "compare")

	return term1:EqualsRaw(term2)
end

AptInt.__lt = function(a: ValidMetamethodArgument, b: ValidMetamethodArgument): boolean
	local term1: AptInt = ArgumentToAptInt(a, "compare")
	local term2: AptInt = ArgumentToAptInt(b, "compare")

	return term1:LowerThanRaw(term2)
end

AptInt.__le = function(a: ValidMetamethodArgument, b: ValidMetamethodArgument): boolean
	local term1: AptInt = ArgumentToAptInt(a, "compare")
	local term2: AptInt = ArgumentToAptInt(b, "compare")

	return term1:LowerOrEqualToRaw(term2)
end

AptInt.__tostring = function(n: AptInt): string
	return n:ToString()
end

AptInt.__len = function(n: AptInt): number
	if n.signum == 0 then return 0 end
	
	local limbs: {number} = n.limbs
	return floor(log10(limbs[#limbs]) + (#limbs - 1) * RADIX_LEN_CONST) + 1
end

return AptInt