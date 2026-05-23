--!native
--!strict
--!optimize 2

local Utils = {}

local Constants = require("../Constants")

const ceil: (number) -> number = math.ceil

const tinsert: ({number}, number) -> () = table.insert
const tcreate: (number, number) -> {number} = table.create
const tclone: ({number}) -> {number} = table.clone
const tmove: ({number}, number, number, number, {number}) -> {number} = table.move

const BASE: number = Constants.BASE
const STEP: number = 16

local pools: {{{number}}} = {}
for i: number = 1, 30_000 // STEP do
	pools[i] = {}
	
	--> add two defaults for each one
	tinsert(pools[i], tcreate(STEP * i, 0))
	tinsert(pools[i], tcreate(STEP * i, 0))
end

function Utils.GetPrealloc(size: number, fallback: {number}?): {number}
	if size < 16 then return tcreate(size, 0) end
	
	local poolNum: number = ceil(size / STEP)
	for i: number = poolNum, poolNum + 4 do
		--> get pool and see if its not empty
		local currPool: {{number}} = pools[i]
		local poolLen: number = #currPool
		if poolLen == 0 then continue end

		local extTbl: {number} = currPool[poolLen]
		currPool[poolLen] = nil
		
		--> correct its size
		local tblLen: number = #extTbl
		if tblLen > size then
			for j: number = tblLen, size + 1, -1 do
				extTbl[j] = nil
			end
			return extTbl
		end
		
		--> too small,. for equal sizes it doesnt run
		for j: number = tblLen + 1, size do
			extTbl[j] = 0
		end
		
		return extTbl
	end
	
	--> failed to find a non-empty pool
	if fallback then return tclone(fallback) end
	return tcreate(size, 0)
end

function Utils.ReturnPrealloc(alloc: {number}): ()
	local size: number = #alloc
	if size < 16 then return end
	
	tinsert(pools[ceil(size / STEP)], alloc)
end

function Utils.StripLeadingZeros(array: {number}): ()
	local len: number = #array
	while len > 0 and array[len] == 0 do
		array[len] = nil
		len -= 1
	end
end

function Utils.GetLower(limbs: {number}, n: number): {number}
	return tmove(limbs, 1, n, 1, {})
end

--> get upper n limbs
function Utils.GetUpper(limbs: {number}, n: number): {number}
	return tmove(limbs, n+1, #limbs, 1, {})
end

--> get limbs from startIdx to endIdx
function Utils.GetSlice(limbs: {number}, startIdx: number, endIdx: number): {number}
	return tmove(limbs, startIdx, endIdx, 1, {})
end

function Utils.LeftShift(limbs: {number}, amount: number, inPlace: boolean?): {number}
	if inPlace then
		tmove(limbs, 1, #limbs, amount + 1, limbs)
		for i: number = 1, amount do
			limbs[i] = 0
		end
		
		return limbs
	end
	
	-- this is the fastest way to leftshift
	return tmove(limbs, 1, #limbs, amount+1, tcreate(amount, 0))
end

function Utils.DivByInt(limbs: {number}, div: number, inPlace: boolean?): ({number}, {number})
	local quotient: {number} = (inPlace and limbs or Utils.GetPrealloc(#limbs, limbs))

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

return Utils