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

export type ValidConstructor = string | number | AptInt | {number} | nil
export type ValidMetamethodArgument = string | number | AptInt

export type AptInt = setmetatable<{
	limbs: {number},
	signum: number,
	
	read clone: (n: AptInt) -> AptInt,
	
	read Negate: (n: AptInt, inPlace: boolean) -> AptInt,

	read LeftShift: (n: AptInt, amount: number) -> AptInt,
	
	read AddRaw: (term: AptInt, term: AptInt) -> AptInt,
	read SubtractRaw: (term: AptInt, term: AptInt) -> AptInt,
	read MultiplyRaw: (factor: AptInt, factor: AptInt) -> AptInt,
	read DivideRaw: (dividend: AptInt, divisor: AptInt) -> (AptInt, AptInt),
	read ModRaw: (n: AptInt, div: AptInt) -> AptInt,
	
	read EqualsRaw: (self: AptInt, num: AptInt) -> boolean,
	read LowerThanRaw: (self: AptInt, num: AptInt) -> boolean,
	read LowerOrEqualToRaw: (self: AptInt, num: AptInt) -> boolean,
	
	read ToString: (n: AptInt) -> string	,
	read ToNumber: (n: AptInt) -> number,
}, typeof(AptInt)>

-- ================================
--> OPTIMIAZTION FUNCTION CONSTANTS
-- ================================

local log10: (number) -> number = math.log10
local log: (number, number?) -> number = math.log
local floor: (number) -> number = math.floor
local ceil: (number) -> number = math.ceil
local max: (number) -> number = math.max
local abs: (number) -> number = math.abs
local sign: (number) -> number = math.sign

local tcreate: <V>(number, V?) -> {V} = table.create
local tinsert: <V>({V}, V) -> () & <V>({V}, number, V) -> () = table.insert
local tremove: <V>({V}, number?) -> V? = table.remove
local tclone: <T>({T}) -> {T} = table.clone

local sformat: (string, ...unknown) -> string = string.format

-- =================
--> NORMAL CONSTANTS
-- =================

local KARATSUBA_THRESHOLD: number = 50 -- in limbs, limit where karatsuba is faster than normal multiplication
local SAFE_UNPACK_THRESHOLD: number = 8000 -- unpack() max size in limbs

local MAX_LOSSLESS_POW: number = 53 -- 2^53
local MAX_LOSSLESS_INT: number = 2^MAX_LOSSLESS_POW-1

local BASE_POW: number = 7 -- MUST SATISFY: 10^((BASE_POW+1) * 2) < 2^53, because of multiplyraw and divideraw
local BASE: number = 10 ^ BASE_POW

--> CONSTRUCTOR
local typeConstructors: {[string]: (any) -> ({number}, number)} = {
	["string"] = function(str: string): ({number}, number)
		local isNegative: boolean = str:sub(1, 1) == "-"
		local strStart: number = isNegative and 2 or 1
		
		local arr: {number} = {}
		
		local i: number = #str
		repeat
			local chars: string = str:sub(max(i - BASE_POW + 1, strStart), i)
			local num: number? = tonumber(chars)
			if not num then break end
			
			i -= BASE_POW
			tinsert(arr, num)
		until i < strStart
		
		return arr, (isNegative and -1 or 1)
	end,

	["number"] = function(num: number): ({number}, number)
		if num == 0 then
			return {0}, 0
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
		local first: any = tbl[1]
		if not first then
			return {0}, 0
		end
		
		--> if is faster than assert, we use if here since its called a lot of times
		if typeof(first) ~= "number" then
			error("attempt to create AptInt from a table with non-int values")
		end
		
		return tbl, 1
	end,

	["nil"] = function(_: nil): ({number}, number)
		return {0}, 0
	end,
}

-- =================
--> HELPER FUNCTIONS
-- =================

local function ArgumentToAptInt(num: ValidMetamethodArgument?, errContext: string): AptInt
	local bigint: AptInt;

	--> make sure toAdd is correct
	if getmetatable(num :: AptInt?) == AptInt then
		bigint = num :: AptInt
	else
		local numType: string = typeof(num)
		
		assert(
			numType ~= "table" and typeConstructors[numType] ~= nil,
			`attempt to perform ({errContext}) on AptInt and {numType}`
		)
		
		bigint = AptInt.new(num)
	end

	return bigint
end

-- Split a digit into its low "d" limbs and its high limbs. For example, split_at(12345, 3) 
-- will extract the 3 final limbs, giving: high=12, low=345.
local function GetKaratsubaLower(int: AptInt, n: number): AptInt
	local limbs: {number} = int.limbs
	
	--> unsure if this is faster.
	if #limbs < SAFE_UNPACK_THRESHOLD then
		-- table.pack is faster here but FOR SOME REASON IT INCLUDES ["N"] IN THE ARRAY TOO?!
		return AptInt.new({unpack(limbs, 1, n)})
	end
	
	local result: AptInt = AptInt.new(tcreate(n, 0))
	local resultlimbs: {number} = result.limbs
	
	for i: number = 1, n do
		resultlimbs[i] = limbs[i]
	end
	
	return result
end

local function GetKaratsubaUpper(int: AptInt, n: number): AptInt
	-- {select(unpack(x))} is faster, but unpack only works up to a certain degree.
	local limbs: {number} = int.limbs

	if #limbs < SAFE_UNPACK_THRESHOLD then
		-- select(n + 1, unpack(limbs)) is wayy faster than {unpack(limbs, n+1, #limbs)}
		return AptInt.new({
			select(n + 1, unpack(limbs)) :: number
		})
	end
	
	local result: AptInt = AptInt.new() -- TODO: tcreate here
	local resultLimbs: {number} = result.limbs
	
	for i: number = n + 1, #limbs do
		tinsert(resultLimbs, limbs[i])
	end
	
	return result
end

local function MultiplyKaratsuba(x: AptInt, y: AptInt): AptInt
	local m2: number = (max(#x.limbs, #y.limbs) + 1)//2

	local low1: AptInt, low2: AptInt = GetKaratsubaLower(x, m2), GetKaratsubaLower(y, m2)
	local high1: AptInt, high2: AptInt = GetKaratsubaUpper(x, m2), GetKaratsubaUpper(y, m2)
	
	local z0: AptInt = low1:MultiplyRaw(low2)
	local z1: AptInt = low1:AddRaw(high1):MultiplyRaw(low2:AddRaw(high2))
	local z2: AptInt = high1:MultiplyRaw(high2)

	-- (z2 × BASE ^ (m2 × 2)) + ((z1 - z2 - z0) × BASE ^ m2) + z0
	-- since base is a power of 10, we can just prepend zeros to avoid slow exponentiation
	local result = z2:LeftShift(m2 * 2)
		:AddRaw(
			(z1:SubtractRaw(z2):SubtractRaw(z0)):LeftShift(m2)
		)
		:AddRaw(z0)
	
	if x.signum ~= y.signum then
		return result:Negate(true)
	end
	
	return result
end

--> divsion stuff
local function CorrectRemainder(self: AptInt, divisor: AptInt, remainder: AptInt)
	local selfSign: number, divSign: number = self.signum, divisor.signum
	local sameSign: boolean = selfSign == divSign
	
	if sameSign then
		if divSign == -1 then
			return remainder:Negate(true)
		end
		
		return remainder
	elseif selfSign == 1 and divSign == -1 and remainder.signum ~= 0 then
		return divisor:AddRaw(remainder)
	elseif remainder.signum ~= 0 then
		return divisor:SubtractRaw(remainder)
	end
	
	return remainder
end

local function TryModExp(limb: number, div: number, base: number): (boolean, number)
	local log: number = log(div, base)
	if log ~= floor(log) or log > BASE_POW then -- log > BASE_POW since each power we check 1 more digit
		return false, 0
	end	
	
	return true, limb % div
end

local function LowerThanAbsolute(x: AptInt, y: AptInt): boolean
	local xLimbs: {number}, yLimbs: {number} = x.limbs, y.limbs
	for i: number = #xLimbs, 1, -1 do
		local xDigit: number, yDigit: number = xLimbs[i], yLimbs[i] or 0
		if xDigit == yDigit then continue end

		return xDigit < yDigit
	end

	return false 
end

local function StripLeadingZeros(n: AptInt)
	local limbs: {number} = n.limbs
	while #limbs > 1 and limbs[#limbs] == 0 do
		tremove(limbs, #limbs)
	end
	if #limbs == 1 and limbs[#limbs] == 0 then
		n.signum = 0
	end
end

-- ====================
--> METATABLE FUNCTIONS
-- ====================

-- Returns a new AptInt from given argument
function AptInt.new(num: ValidConstructor): AptInt
	local limbs: {number}, signum: number = typeConstructors[typeof(num)](num)
	
	return setmetatable({
		limbs = limbs,
		signum = signum
	}, AptInt) :: AptInt
end

-- Returns a copy of the AptInt.
function AptInt.clone(n: AptInt): AptInt
	return setmetatable({
		limbs = tclone(n.limbs),
		signum = n.signum
	}, AptInt) :: AptInt
end

-- Returns a new AptInt with its sign flipped.
function AptInt:Negate(inPlace: boolean): AptInt
	if inPlace then
		self.signum = -self.signum
		return self
	end
	
	local result: AptInt = self:clone()
	result.signum = -result.signum
	
	return result
end
-- =====================
--> ARITHMETIC FUNCTIONS
-- =====================

-- Returns a new AptInt = x, whose value is equal to a + b.
function AptInt:AddRaw(term: AptInt): AptInt
	local selfSign: number, summandSign: number = self.signum, term.signum
	local sameSign: boolean = selfSign == summandSign
	
	--> CASES
	if summandSign == 0 then
		return self:clone()
	elseif selfSign == 0 then
		return term:clone()
	elseif selfSign == -1 and summandSign == 1 then -- -a+b = b+(-a) = b-a
		return (self:Negate(false):SubtractRaw(term)):Negate(true)
	elseif not sameSign then -- +a+(-b)=a-b
		return self:SubtractRaw(term:Negate(true))
	end
	
	local limbsSummand: {number}, limbsSelf: {number} = term.limbs, self.limbs
	local limbsToAdd: number = max(#limbsSelf, #limbsSummand)

	local result: AptInt = AptInt.new(tcreate(limbsToAdd, 0))

	--> from right to left
	local carry: number = 0
	for i: number = 1, limbsToAdd do
		local sum: number = (limbsSelf[i] or 0) + (limbsSummand[i] or 0) + carry
		
		if sum >= BASE then
			carry = 1
			sum = sum - BASE
		else
			carry = 0
		end
		
		result.limbs[i] = sum
	end

	if carry > 0 then
		result.limbs[limbsToAdd + 1] = carry
	end
	
	result.signum = (if sameSign and selfSign == -1 then -1 else 1)
	return result
end

-- Returns a new AptInt = x, whose value is equal to a - b.
function AptInt:SubtractRaw(term: AptInt): AptInt
	local selfSign: number, termSign: number = self.signum, term.signum
	local sameSign: boolean = (selfSign == termSign)
	
	--> CASES
	if termSign == 0 then
		return self:clone()
	elseif selfSign == 0 then
		return term:clone()
	elseif termSign == -1 and selfSign == 1 then -- a - (-b) = a + b
		return term:Negate(false):AddRaw(self)
	elseif sameSign and selfSign == -1 then -- (-a-(-b)) b-a
		return (self:Negate(false):SubtractRaw(term:Negate(false))):Negate(true)
	end
	
	if self:LowerThanRaw(term) then
		return term:SubtractRaw(self):Negate(true)
	end
	
	local result: AptInt = AptInt.new()
	
	local limbsSubrahend: {number} = term.limbs

	--> from right to left
	local borrow: number = 0
	for i: number, digit: number in self.limbs do
		local diff: number = digit - (limbsSubrahend[i] or 0) - borrow
		if diff < 0 then
			borrow = 1
			diff = diff + BASE
		else
			borrow = 0
		end
		
		result.limbs[i] = diff
	end
	
	StripLeadingZeros(result)
	
	result.signum = 1
	return result
end

-- Returns a AptInt = x, whose value is equal to a * b.
function AptInt:MultiplyRaw(factor: AptInt): AptInt
	local selfSign: number, factorSign: number = self.signum, factor.signum
	
	--> CASES
	if selfSign == 0 or factorSign == 0 then
		return AptInt.new()
	end
	
	local selflimbs: {number} = self.limbs
	local factorlimbs: {number} = factor.limbs
	
	if #selflimbs > KARATSUBA_THRESHOLD and #factorlimbs > KARATSUBA_THRESHOLD then
		return MultiplyKaratsuba(self, factor)
	end

	local result: AptInt = AptInt.new(tcreate(#selflimbs, 0))
	
	-- do normal o(n^2) schoolgrade multiplication
	for i: number, factorDigit: number in factorlimbs do
		local carry: number = 0
		local prependedZeros: number = i - 1

		if factorDigit == 0 then
			continue
		elseif factorDigit == 1 then
			result = result:AddRaw(self)
			continue
		end
		
		--> TODO: get rid of mulResult
		local mulResult: AptInt = AptInt.new(tcreate(prependedZeros + #factorlimbs, 0))
		
		for j: number, selfDigit: number in selflimbs do
			local mul: number = selfDigit * factorDigit + carry
			
			if mul > BASE then
				carry = mul // BASE
				mul = mul % BASE
			else
				carry = 0
			end
			
			mulResult.limbs[j + prependedZeros] = mul
		end
		
		--> carry can "ripple" through the number. for example: 9999 + 1
		while carry > 0 do
			local last: number? = mulResult.limbs[#mulResult.limbs + 1]
			local sum: number = (last or 0) + carry
			
			if sum >= BASE then
				carry = 1
				sum = sum - BASE
			else
				carry = 0
			end
			
			mulResult.limbs[#mulResult.limbs + 1] = sum
		end
		
		result = result:AddRaw(mulResult)
	end
	
	result.signum = (selfSign ~= factorSign and -1 or 1)
	return result
end

-- Returns the quotient and remainder of a / b.
function AptInt:DivideRaw(divisor: AptInt): (AptInt, AptInt)
	--> we use knuths algorithm D for division
	--> when we have a single limbed divisor, we can skip normalizing/unnormalizing for immense performance gains
	local divSign: number, selfSign: number = divisor.signum, self.signum
	local sameSign: boolean = divSign == selfSign
	
	--> CASES (oh dear..)
	--> TODO: refactor
	if divSign == 0 or selfSign == 0 then -- dividing by 0
		return AptInt.new(), AptInt.new()
	elseif LowerThanAbsolute(self, divisor) then
		if selfSign == 1 and divSign == -1 then
			return AptInt.new({-1}), divisor:AddRaw(self)
		elseif selfSign == -1 and divSign == 1 then
			return AptInt.new({-1}), divisor:SubtractRaw(self:Negate(false))
		elseif sameSign and divSign == -1 then
			return AptInt.new(), self:clone()
		end
		
		return AptInt.new(), self:clone()
	elseif self:EqualsRaw(divisor) then -- dividing x/x = 1
		return AptInt.new({1}), AptInt.new()
	elseif self:Negate(false):EqualsRaw(divisor) or self:EqualsRaw(divisor:Negate(false)) then -- -x/x = -1
		return AptInt.new({-1}), AptInt.new()
	end
	
	local U: {number}, V: {number} = self.limbs, divisor.limbs
	if #U == 1 and #V == 1 then -- single limb division
		local mod: number = U[1] % V[1]
		local q: number = floor(U[1] * selfSign / V[1] * divSign)
		return AptInt.new({q}), AptInt.new({mod})
	end
	
	local divisorSinglelimb: boolean = #V == 1
	
	--> d0. defs
	local n: number = #V
	local m: number = #U - n
	
	--> d1. normalize (get Vn and Un)
	local Vn: {number}, Un: {number}, D: number?
	if divisorSinglelimb then
		Un, Vn = (self :: AptInt):clone().limbs, {divisor.limbs[1]}
	else
		--> TODO: we lose most performance here in MultiplyRaw
		--> because the limb size for divisor & self is big but the limb size for D is 1
		--> because knuths corrects, we should choose D to be a power of 10 and then left shift using base 10
		D = BASE // (V[n] + 1)
		local Dint: AptInt = AptInt.new(D)
		Vn = divisor:MultiplyRaw(Dint).limbs
		Un = (self :: AptInt):MultiplyRaw(Dint).limbs
	end
	
	local Vnn: number = Vn[n]
	local penultimateVn: number = Vn[n-1] or 0

	local quotient: AptInt = AptInt.new(tcreate(m + 1, 0))
	
	--> d2. init j
	local qhat: number, rhat: number = 0, 0
	for j: number = m, 0, -1 do
		--> d3. calculate qhat and rhat
		
		-- bigints for qhat and rhat are not needed, because un[x] is at most BASE
		-- currently, BASE * BASE + BASE < 2^53
		local nPlusJ: number = n + j + 1
		local top: number = (Un[nPlusJ] or 0) * BASE + (Un[nPlusJ - 1] or 0)
		qhat = top // Vnn
		rhat = top % Vnn
		
		if qhat == 0 then continue end
		
		--> first correction
		if divisorSinglelimb then
			while (qhat >= BASE) or (qhat * (Vn[n - 1] or 0) > rhat * BASE + (Un[nPlusJ - 2] or 0)) do
				qhat -= 1
				rhat += Vnn
				if rhat >= BASE then break end
			end
		elseif qhat * penultimateVn > rhat * BASE + (Un[nPlusJ - 2] or 0) then
			qhat -= 1
			rhat += Vnn

			--> second correction
			if rhat < BASE and qhat * penultimateVn > rhat * BASE + (Un[nPlusJ - 2] or 0) then
				qhat -= 1
			end
		end

		--> d4. multiply & subtract
		local carry: number = 0
		local borrow: number = 0

		for i = 1, n do
			local p: number = qhat * Vn[i] + carry
			carry = p // BASE
			local pDigit: number = p % BASE
			
			local diff: number = Un[i + j] - pDigit - borrow
			if diff < 0 then
				borrow = 1
				Un[i + j] = diff + BASE
				continue
			end
			
			Un[i + j] = diff
			borrow = 0
		end
		
		local lastSub: number = (Un[nPlusJ] or 0) - carry - borrow
		Un[nPlusJ] = lastSub

		--> d6. add back
		if lastSub >= 0 then
			quotient.limbs[j + 1] = qhat
			continue
		end
		
		quotient.limbs[j + 1] = qhat - 1
		carry = 0

		for i: number = 1, n do
			local sum: number = Un[i + j] + Vn[i] + carry

			if sum >= BASE then
				carry = 1
				sum = sum - BASE
			else
				carry = 0
			end

			Un[i + j] = sum
		end

		Un[nPlusJ] = (Un[nPlusJ] + carry) % BASE
	end
	
	local remainder: AptInt = AptInt.new(Un)
	
	--> d8. unnormalize
	if not divisorSinglelimb then
		local carry: number = 0
		local rmLimbs: {number} = remainder.limbs
		for i: number = #rmLimbs, 1, -1 do
			local x: number = carry * BASE + rmLimbs[i]
			rmLimbs[i] = x // D :: number
			carry = x % D :: number
		end
	end
	
	StripLeadingZeros(remainder)
	StripLeadingZeros(quotient)
	
	--> return
	remainder = CorrectRemainder(self, divisor, remainder)
	if not sameSign then
		quotient:Negate(true)
	end
	
	return quotient, remainder
end

function AptInt:ModRaw(div: AptInt): AptInt
	--> TODO: THIS IS REAAAAALLY UGLY.
	local divLimbs: {number} = div.limbs
	local divLimbAmount: number, selfLimbAmount: number = #divLimbs, #(self :: AptInt).limbs

	local selfSign: number, divSign: number = self.signum, div.signum

	local divFirst: number = divLimbs[1] * divSign
	local selfFirst: number = self.limbs[1] * selfSign

	if divSign == 0 or (divLimbAmount == 1 and abs(divFirst) == 1) then
		return AptInt.new()
	elseif selfLimbAmount == 1 and divLimbAmount == 1 then
		return AptInt.new({selfFirst % divFirst})
	elseif divLimbAmount ~= 1 then
		local _: AptInt, r: AptInt = self:DivideRaw(div)
		return r
	end
	
	--> single limb divisor optimizations
	-- we check trymodexp which is expensive and uses math.log.
	-- performance difference shouldnt matter that much, since
	-- single limb division already is insanely fast,
	-- but since we check once for each number, it adds up
	
	--> TODO: add argument that disables this modexp
	local success: boolean, mod: number = TryModExp(selfFirst, divFirst, 2) -- 2
	if success then return AptInt.new({mod}) end
	
	success, mod = TryModExp(selfFirst, divFirst, 5) -- 5
	if success then return AptInt.new({mod}) end
	
	success, mod =  TryModExp(selfFirst, divFirst, 10) -- 10
	if success then return AptInt.new({mod}) end
	
	local _: AptInt, r: AptInt = self:DivideRaw(div)
	return r
end

-- ==================
--> QoL FUNCTIONS
-- ==================

-- Returns a new string representation of an AptInt
function AptInt:ToString(): string
	local str: string = (self.signum == -1 and "-" or "")
	if self.signum == 0 then
		return "0"
	end
	
	local limbs: {number} = self.limbs
	str ..=limbs[#limbs]
	
	local formatStr: string = `%0{BASE_POW}d`
	
	--> from left to right
	for i: number = #limbs - 1, 1, -1 do
		str ..= sformat(formatStr, limbs[i]) -- prepend dem zeros
	end

	return str
end

-- Returns a double whose value is equal to tonumber(x)
function AptInt:ToNumber(): number
	return tonumber(self:ToString()) :: number -- faster than doing math.log10 stuff and blablabla
end

-- ==================
--> COMPARISON FUNCTIONS
-- ==================

-- Returns true if self == num, false if not.
function AptInt:EqualsRaw(num: AptInt): boolean
	if (#(self :: AptInt).limbs ~= #num.limbs) or (self.signum ~= num.signum) then
		return false
	end
	
	for i: number, selfDigit: number in self.limbs do
		if selfDigit ~= num.limbs[i] then
			return false
		end
	end
	
	return true
end

-- Returns true if self < num, false if not.
function AptInt:LowerThanRaw(num: AptInt): boolean
	local selfSign: number, numSign: number = self.signum, num.signum
	local selfLen: number, numLen: number = #self.limbs, #num.limbs
	
	--> check sign
	if selfSign < numSign then
		return true
	end
	
	local bothNegative: boolean = (selfSign == numSign and selfSign == -1)
	--> check their lengths. for negative, the lowest is with the most limbs, and for positive its the lowest
	if bothNegative and selfLen > numLen then
		return true
	elseif selfLen < numLen then -- both positive
		return true
	end
	
	local selflimbs: {number}, numlimbs: {number} = self.limbs, num.limbs
	for i: number = #selflimbs, 1, -1 do
		local sDigit: number, nDigit: number = selflimbs[i], numlimbs[i] or 0
		if sDigit == nDigit then continue end
		
		if bothNegative then
			return sDigit > nDigit
		end
		
		return sDigit < nDigit
	end

	return false 
end

-- Returns true if self <= num, false if not.
function AptInt:LowerOrEqualToRaw(num: AptInt): boolean
	local selfSign: number, numSign: number = self.signum, num.signum
	local selfLen: number, numLen: number = #self.limbs, #num.limbs

	--> check sign
	if selfSign <= numSign then
		return true
	end

	local bothNegative: boolean = (selfSign == numSign and selfSign == -1)
	--> check their lengths. for negative, the lowest is with the most limbs, and for positive its the lowest
	if bothNegative and selfLen >= numLen then
		return true
	elseif selfLen <= numLen then -- both positive
		return true
	end

	local selflimbs: {number}, numlimbs: {number} = self.limbs, num.limbs
	for i: number = #selflimbs, 1, -1 do
		local sDigit: number, nDigit: number = selflimbs[i], numlimbs[i] or 0
		if sDigit == nDigit then continue end

		if bothNegative then
			return sDigit >= nDigit
		end

		return sDigit <= nDigit
	end
	
	return true 
end

-- ==================
--> "BOOLEAN" FUNCTIONS
-- ==================

-- Returns a new AptInt = x, where self * 10^(BASE*amount) = x
function AptInt:LeftShift(amount: number): AptInt
	local result: AptInt = self:clone()
	
	local tbl: {number} = result.limbs
	
	for i: number = 1, amount do
		tinsert(tbl, 1, 0)
	end
	
	return result
end

-- ============
--> METAMETHODS
-- ============

AptInt.__unm = function(num: ValidMetamethodArgument): AptInt
	local bigint: AptInt = ArgumentToAptInt(num, "unm")
	
	return bigint:Negate(false)
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

AptInt.__eq = function(a: ValidMetamethodArgument, b: ValidMetamethodArgument): boolean
	local term1: AptInt = ArgumentToAptInt(a, "eq")
	local term2: AptInt = ArgumentToAptInt(b, "eq")
	
	return term1:EqualsRaw(term2)
end

AptInt.__lt = function(a: ValidMetamethodArgument, b: ValidMetamethodArgument): boolean
	local term1: AptInt = ArgumentToAptInt(a, "lt")
	local term2: AptInt = ArgumentToAptInt(b, "lt")
	
	return term1:LowerThanRaw(term2)
end

AptInt.__le = function(a: ValidMetamethodArgument, b: ValidMetamethodArgument): boolean
	local term1: AptInt = ArgumentToAptInt(a, "le")
	local term2: AptInt = ArgumentToAptInt(b, "le")

	return term1:LowerOrEqualToRaw(term2)
end

AptInt.__tostring = function(n: AptInt): string
	return n:ToString()
end

AptInt.__len = function(n: AptInt): number
	return rawlen(n.limbs)
end

-- ===========
--> EXTENSIONS
-- ===========
function AptInt.Extend(func: (typeof(AptInt)) -> ())
	func(AptInt)
end

return AptInt
