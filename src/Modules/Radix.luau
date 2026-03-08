--!native
--!strict
--!optimize 2

local Radix = {}

local Constants = require("../Constants")
local Add = require("./Add")
local Mul = require("./Mul")

local tcreate: (number, {number}) -> {{number}} = table.create
local tinsert: ({number}, number) -> () = table.insert

local ceil: (number) -> number = math.ceil
local max: (number, number) -> number = math.max

--> -1 because 2^BASE < RADIX_CHUNK_SIZE
local RADIX_CHUNK_SIZE: number = Constants.RADIX_CHUNK_SIZE / 10
local RADIX_CHUNK_POW: number = Constants.RADIX_CHUNK_POW - 1

local squareCache: {{number}} = {}
local function squareBase(b: {number}, depth: number)
	if squareCache[depth] then return squareCache[depth] end
	
	local sq: {number} = Mul.MulLimbs(b, b) 
	squareCache[depth] = sq
	
	return sq
end

function Radix.fromString(str: string): ({number}, number)
	--> Algorithm 1.25: FastIntegerInput
	--> https://maths-people.anu.edu.au/~brent/pd/mca-cup-0.5.9.pdf
	if str == "0" then return {}, 0 end
	--> KEEP IN MIND: l = bigint array, b = also bigint
	
	local isNegative: boolean = str:sub(1, 1) == "-"
	if isNegative then
		str = str:sub(2, #str)
	end
	
	--> l = [val(s_0), val(s_1) ... val(s_m-1)]
	local strLen: number = #str
	local l: {{number}} = tcreate(strLen // RADIX_CHUNK_POW, {0})
	local idx: number = 1
	
	for i: number = strLen, 1, -RADIX_CHUNK_POW do
		local chunk: string = str:sub(max(1, i - RADIX_CHUNK_POW + 1), i)
		
		l[idx] = {tonumber(chunk) or 0}
		idx += 1
	end
	--print(l)
	local b: {number}, k: number = {RADIX_CHUNK_SIZE}, #l -- (b, k) <- (B, m)
	local depth: number = 1
	
	while k > 1 do
		local lIdx: number = 1
		local new: {{number}} = tcreate(ceil(k/2), {0})
		for i: number = 1, k - 1, 2 do
			local bli1: {number} = Mul.MulLimbs(l[i + 1], b)
			new[lIdx] = Add.AddLimbs(l[i], bli1, true) -- [l_x + bl_x+1, ... ,l_k-2 + bl_k-1]
			lIdx += 1
		end
		
		--> if l odd l[k-1] = unchanged
		if k % 2 == 1 then
			new[lIdx] = l[k]
		end
		
		l = new
		b = squareBase(b, depth); depth += 1
		k = ceil(k/2)
	end
	
	return l[1], isNegative and -1 or 1
end

return Radix