--!native
--!strict
--!optimize 2

local Utils = {}

local Constants = require("../Constants")

const ceil: (number) -> number = math.ceil
const max: (number, number) -> number = math.max 
const abs: (number) -> number = math.abs

const tinsert: ({{number}}, {number}) -> () = table.insert
const tcreate: (number, number) -> {number} = table.create
const tclone: ({number}) -> {number} = table.clone
const tmove: ({number}, number, number, number, {number}) -> {number} = table.move
const tclear: ({{number}}) -> () = table.clear

const BASE: number = Constants.BASE
const PREALLOC_POOL_STEP: number = Constants.PREALLOC_POOL_STEP
const ZEROS: {number} = tcreate(240_000, 0)

--> a better idea would be to sort these into buckets of size PREALLOC_POOL_STEP
--> ... i tried that, and it somehow had worse performance than this approach. way worse.
--> why are you like this, luau?
local pools: {{number}} = {}
local currPoolLen: number = 0
local function CleanPool()
	table.clear(pools)
end

function Utils.GetAlloc(size: number, fallback: {number}?): {number}
	--> sometimes size can be negative from getlower/upper/slice
	size = max(size, 0)
	if size < PREALLOC_POOL_STEP then return tcreate(size, 0) end
	
	if currPoolLen == 0 then
		if fallback then return tclone(fallback) end
		return tcreate(size, 0)
	end

	local extTbl: {number} = pools[currPoolLen]
	local tblLen: number = #extTbl
	pools[currPoolLen] = nil
	currPoolLen -= 1

	--> correct its size
	if tblLen > size then
		for j: number = size + 1, tblLen do
			extTbl[j] = nil
		end
		return extTbl
	end
		
	--> too small, for equal sizes it doesnt run
	for j: number = tblLen + 1, size do
		extTbl[j] = 0
	end
		
	return extTbl
end

function Utils.ReturnAlloc(alloc: {number}): ()
	if #alloc < PREALLOC_POOL_STEP then return end
	currPoolLen += 1
	tinsert(pools, alloc)
end

function Utils.StripLeadingZeros(array: {number}): ()
	local len: number = #array
	while len > 0 and array[len] == 0 do
		array[len] = nil
		len -= 1
	end
end

--> get lower n limbs
function Utils.GetLower(limbs: {number}, n: number): {number}
	return tmove(limbs, 1, n, 1, Utils.GetAlloc(n))
end

--> get upper n limbs
function Utils.GetUpper(limbs: {number}, n: number): {number}
	local moveTo: {number} = Utils.GetAlloc(#limbs - n)
	return tmove(limbs, n+1, #limbs, 1, moveTo)
end

--> get limbs from startIdx to endIdx
function Utils.GetSlice(limbs: {number}, startIdx: number, endIdx: number): {number}
	local moveTo: {number} = Utils.GetAlloc(endIdx - startIdx + 1)
	return tmove(limbs, startIdx, endIdx, 1, moveTo)
end

function Utils.LeftShift(limbs: {number}, amount: number, inPlace: boolean?): {number}
	local limbLen: number = #limbs
	if limbLen == 0 then return limbs end

	if inPlace then
		tmove(limbs, 1, limbLen, amount + 1, limbs)
		for i: number = 1, amount do
			limbs[i] = 0
		end
		return limbs
	end

	local allocTbl: {number} = Utils.GetAlloc(limbLen + amount)
	tmove(ZEROS, 1, amount, 1, allocTbl)
	return tmove(limbs, 1, limbLen, amount + 1, allocTbl)
end

function Utils.DivByInt(limbs: {number}, div: number, inPlace: boolean?): ({number}, {number})
	local quotient: {number} = (inPlace and limbs or Utils.GetAlloc(#limbs, limbs))

	local carry: number = 0
	for i: number = #limbs, 1, -1 do
		local x: number = limbs[i] + carry * BASE
		local qDigit: number = x // div

		carry = x - qDigit * div
		quotient[i] = qDigit
	end

	Utils.StripLeadingZeros(quotient)
	if carry == 0 then
		return quotient, {}
	end

	return quotient, {carry}
end

--> UGLY: rebuild pool every once in a while to avoid super high memory
task.spawn(function()
	while task.wait(60) do
		CleanPool()
	end
end)

return Utils