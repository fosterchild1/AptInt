<p align="center"><img src="https://github.com/fosterchild1/AptInt/blob/main/resources/text.png" width="659" height="288"></p>

## <p align="center">Lightweight, highest performance BigInteger library for Luau</p>
### <p align="center">AptInt is the fastest luau implementation of BigInteger, designed for working with numbers over 10,000 digits long.</p>

# Overview
This library provides [arbitrary precision arithmetic](https://en.wikipedia.org/wiki/Arbitrary-precision_arithmetic) capabilities implemented in just Luau. It uses a 2^24 word size to store numbers and can easily be configured to your liking.

This library provides:
- Functionality for all arithmetic operations ([`:AddRaw()` `:SubtractRaw()` `:MultiplyRaw()` `:DivideRaw()` `:PowRaw()` `:ModRaw()` `:sqrt()`](https://github.com/fosterchild1/AptInt/blob/main/docs/documentation.md#arithmetic))
- Comparison functions ([`:LowerThanRaw()` `:EqualsRaw()` `:LowerOrEqualToRaw()`](https://github.com/fosterchild1/AptInt/blob/main/docs/documentation.md#comparison))
- Metamethod support (`+ - * / ^ % < <= == >= =`)
- Limb-wise [Left shift and right shift](https://github.com/fosterchild1/AptInt/blob/main/docs/documentation.md#other)
- Conversion functions ([`:ToString()` `:ToNumber()`](https://github.com/fosterchild1/AptInt/blob/main/docs/documentation.md#conversion))
- Extra utilities such as ([`:Abs()` `:Min()` `:Max()`](https://github.com/fosterchild1/AptInt/blob/main/docs/documentation.md#extensions))

The implementations are as performant as possible, so they have no safety checks, with the exception of the metamethods.

# Usage
Usage Documentation can be found [here](https://github.com/fosterchild1/AptInt/blob/main/docs/usage.md).<br/>
Algorithm choice can be found [here](https://github.com/fosterchild1/AptInt/blob/main/docs/algorithms.md).

# What makes it so fast?
AptInt uses the Karatsuba and Toom-Cook3 algorithms for multiplication, Knuths algorithm D for division, Karatsuba sqrt for finding the square root and more. Alongside these algorithms, it uses many techniques to shave off hundreds of milliseconds of computing time.

It also utilizes the full power of native code generation to get even faster results.

# Benchmarks
Note that these were done on an i7-10750H CPU. The benchmark script can be found in [/bench/](https://github.com/fosterchild1/AptInt/blob/main/bench/bench.luau).<br/>
The results are updated every time the performance gets improved. They are also generally ~1.3x faster if running on the roblox server.<br/>
For division, we do a 2NxN division. (2N = digit count)

| Digit count | Addition | Subtraction | Multiplication | Division | Square root |
| ---  | --- | --- | --- | --- | --- |
| 1 | 1μs | 1μs | 1μs | 6μs | 7μs |
| 50 | 1μs | 3μs | 4μs | 19μs | 40μs |
| 100 | 2μs | 7μs | 6μs | 31μs | 157μs |
| 500 | 5μs | 9μs | 56μs | 114μs | 311μs |
| 1,000 | 7μs | 13μs | 225μs | 153μs | 468μs |
| 5,000 | 23μs | 30μs | 3ms | 2ms | 2ms |
| 10,000 | 57μs | 74μs | 7ms | 8ms | 5ms |
| 50,000 | 209μs | 243μs | 75ms | 105ms | 67ms |
| 100,000 | 389μs | 396μs | 218ms | 195ms | 153ms |
