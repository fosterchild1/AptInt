export type AptIntMetatable = {
	read __index: AptInt,
	read __unm: (num: AptInt) -> AptInt,
	read __add: (a: ValidMetamethodArgument, b: ValidMetamethodArgument) -> AptInt,
	read __sub: (a: ValidMetamethodArgument, b: ValidMetamethodArgument) -> AptInt,
	read __mul: (a: ValidMetamethodArgument, b: ValidMetamethodArgument) -> AptInt,
	read __div: (a: ValidMetamethodArgument, b: ValidMetamethodArgument) -> AptInt,
	read __idiv: (a: ValidMetamethodArgument, b: ValidMetamethodArgument) -> AptInt,
	read __mod: (a: ValidMetamethodArgument, b: ValidMetamethodArgument) -> AptInt,
	read __pow: (a: ValidMetamethodArgument, b: ValidMetamethodArgument) -> AptInt,
	read __eq: (a: ValidMetamethodArgument, b: ValidMetamethodArgument) -> boolean,
	read __lt: (a: ValidMetamethodArgument, b: ValidMetamethodArgument) -> boolean,
	read __le: (a: ValidMetamethodArgument, b: ValidMetamethodArgument) -> boolean,
	read __tostring: (n: AptInt) -> string,
	read __len: (n: AptInt) -> number,
}

export type AptIntData = {
	limbs: {number},
	signum: number,
}

export type AptInt = setmetatable<AptIntData & AptIntAPI, AptIntMetatable>

export type AptIntAPI = {
	read clone: (n: AptInt) -> AptInt,
	read Negate: (n: AptInt, inPlace: boolean?) -> AptInt,

	read AddRaw: (self: AptInt, term: AptInt, inPlace: boolean?) -> AptInt,
	read SubtractRaw: (self: AptInt, term: AptInt, inPlace: boolean?) -> AptInt,
	read MultiplyRaw: (self: AptInt, factor: AptInt) -> AptInt,
	read DivideRaw: (self: AptInt, divisor: AptInt) -> (AptInt, AptInt),
	read ModRaw: (self: AptInt, div: AptInt) -> AptInt,
	read PowRaw: (self: AptInt, pow: AptInt) -> AptInt,
	read sqrt: (self: AptInt) -> AptInt,

	read EqualsRaw: (self: AptInt, num: AptInt) -> boolean,
	read LowerThanRaw: (self: AptInt, num: AptInt) -> boolean,
	read LowerOrEqualToRaw: (self: AptInt, num: AptInt) -> boolean,

	read LeftShift: (self: AptInt, n: number) -> AptInt,
	read RightShift: (self: AptInt, n: number) -> AptInt,

	read ToString: (self: AptInt) -> string,
	read ToNumber: (self: AptInt) -> number,
	
	read Abs: (self: AptInt, inPlace: boolean?) -> AptInt,
	read Min: (self: AptInt, ...AptInt) -> AptInt,
	read Max: (self: AptInt, ...AptInt) -> AptInt,
}

export type ValidConstructor = string | number | {number} | nil
export type ValidMetamethodArgument = string | number | AptInt

return {}