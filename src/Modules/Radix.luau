--!native
--!strict
--!optimize 2

local Radix = {}

local Constants = require("../Constants")
local Utils = require("./Utils")
local Add = require("./Add")
local Mul = require("./Mul")

--> FUNCTION CONSTANTS
const tcreate: <V>(number, V?) -> {V} = table.create
const tclone: ({number}) -> {number} = table.clone
const tinsert: ({number}, number) -> () = table.insert
const tconcat: ({string}) -> string = table.concat

const ceil: (number) -> number = math.ceil
const floor: (number) -> number = math.floor
const log10: (number) -> number = math.log10
const max: (number, number) -> number = math.max

const sformat: (string, number) -> string = string.format

--> -1 because 2^BASE < RADIX_CHUNK_SIZE
const RADIX_CHUNK_SIZE: number = Constants.RADIX_CHUNK_SIZE
const RADIX_CHUNK_POW: number = Constants.RADIX_CHUNK_POW - 1
const BASE: number = Constants.BASE

local squareCache: {{number}} = {}

local function SquareBase(b: {number}, depth: number): {number}
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
		str = str:sub(2)
	end
	
	--> l = [val(s_0), val(s_1) ... val(s_m-1)]
	local strLen: number = #str
	local l: {{number}} = tcreate(strLen // RADIX_CHUNK_POW)
	local idx: number = 1
	
	for i: number = strLen, 1, -RADIX_CHUNK_POW do
		local chunk: string = str:sub(max(1, i - RADIX_CHUNK_POW + 1), i)
		
		l[idx] = {tonumber(chunk) :: number}
		idx += 1
	end
	--print(l)
	local b: {number}, k: number = {RADIX_CHUNK_SIZE / 10}, #l -- (b, k) <- (B, m)
	local depth: number = 1
	
	while k > 1 do
		local lIdx: number = 1
		local new: {{number}} = tcreate(ceil(k/2))
		
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
		b = SquareBase(b, depth); depth += 1
		k = ceil(k/2)
	end
	
	return l[1], isNegative and -1 or 1
end

--> TODO: FastIntegerOutput 1.26
function Radix.ToString(limbs: {number}): string
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

		Utils.StripLeadingZeros(clone)
	end

	local str: string = tconcat(chunks):gsub("^0+", "") -- removes leading zeros, fast
	return str
end

return table.freeze(Radix)