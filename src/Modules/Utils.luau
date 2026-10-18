--!native
--!strict
--!optimize 2

local Utils = {}

local Constants = require("../Constants")

const floor: (number) -> number = math.floor
const ceil: (number) -> number = math.ceil
const max: (number, number) -> number = math.max 
const abs: (number) -> number = math.abs

const tinsert: ({{number}}, {number}) -> () = table.insert
const tcreate: (number, number) -> {number} = table.create
const tclone: ({number}) -> {number} = table.clone
const tmove: ({number}, number, number, number, {number}) -> {number} = table.move
const tclear: ({any}) -> () = table.clear

const BASE: number = Constants.BASE
const ALLOC_MIN_SIZE: number = Constants.ALLOC_MIN_SIZE
const ALLOC_POOL_SIZE: number = Constants.ALLOC_POOL_SIZE
const ALLOC_POOL_MAX_ENTRIES: number = Constants.ALLOC_POOL_MAX_ENTRIES

const ZEROS: {number} = tcreate(300_000, 0)
const EMPTY: {number} = {}

local tblPools: {{{number}}} = {}
for i: number = 1, 300_000//ALLOC_POOL_SIZE do
	local pool: {{number}} = tcreate(ALLOC_POOL_MAX_ENTRIES)
	
	--> initialize it with a small pool of tables
	if i <= 128 then
		for _: number = 1, ALLOC_POOL_MAX_ENTRIES/2 do
			tinsert(pool, tcreate(i * ALLOC_POOL_SIZE, 0))
		end
	end
	
	tinsert(tblPools, pool)
end

function Utils.GetAlloc(size: number, fallback: {number}?, ctx): {number}
	size = max(size, 0)
	
	if size < ALLOC_MIN_SIZE then
		if fallback then return tclone(fallback) end
		return tcreate(size, 0)
	end
	
	local idx: number = ceil(size / ALLOC_POOL_SIZE)
	local pool: {{number}} = tblPools[idx]
	local numTbls: number = pool and #pool or 0
	
	--> if pool is empty, try the next one
	if numTbls == 0 then
		pool = tblPools[idx + 1]
		numTbls = #pool
	end
	
	if numTbls > 0 then
		local extTbl: {number} = pool[numTbls]
		pool[numTbls] = nil
		
		if #extTbl == size then return extTbl end -- no change needed
		tclear(extTbl)
		return tmove(ZEROS, 1, size, 1, extTbl)
	end
	
	return tcreate(size, 0)
end

function Utils.ReturnAlloc(alloc: {number}): ()
	local size: number = #alloc
	if size < ALLOC_MIN_SIZE then return end

	local pool: {{number}} = tblPools[ceil(size / ALLOC_POOL_SIZE)]
	if not pool or #pool >= ALLOC_POOL_MAX_ENTRIES then return end
	
	tinsert(pool, alloc)
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


function Utils.DivByReciprocal(limbs: {number}, div: number, inPlace: boolean?): ({number}, {number})
	local quotient: {number} = (inPlace and limbs or Utils.GetAlloc(#limbs, limbs))

	local invDiv: number = 1/div
	local carry: number = 0
	for i: number = #limbs, 1, -1 do
		local x: number = limbs[i] + carry * BASE
		local qDigit: number = floor(x * invDiv)

		carry = x - qDigit * div
		quotient[i] = qDigit
	end

	Utils.StripLeadingZeros(quotient)
	if carry == 0 then
		return quotient, {}
	end

	return quotient, {carry}
end

return Utils