<p align="center"><img src="https://github.com/fosterchild1/AptInt/blob/main/resources/text.png" width="659" height="288"></p>

## <p align="center">Lightweight, highest performance BigInteger library for Luau</p>
### <p align="center">AptInt is THE fastest luau implementation of BigInteger, designed for working with numbers over 10,000 digits long.</p>

# Overview
This library provides [arbitrary precision arithmetic](https://en.wikipedia.org/wiki/Arbitrary-precision_arithmetic) capabilities implemented in just Luau. It uses a 2^24 word size to store numbers and can easily be configured to your liking.

This library provides:
- Functionality for all arithmetic operations ([`:AddRaw()` `:SubtractRaw()` `:MultiplyRaw()` `:DivideRaw()` `:PowRaw()` `:ModRaw()` `:sqrt()`](https://github.com/fosterchild1/AptInt/blob/main/docs/usage.md#arithmetic))
- Comparison functions ([`:LowerThanRaw()` `:EqualsRaw()` `:LowerOrEqualToRaw()`](https://github.com/fosterchild1/AptInt/blob/main/docs/usage.md#comparison))
- Metamethod support (`+ - * / ^ % < <= == >= =`)
- Limb-wise [Left shift and right shift](https://github.com/fosterchild1/AptInt/blob/main/docs/usage.md#other)
- Conversion functions ([`:ToString()` `:ToNumber()`](https://github.com/fosterchild1/AptInt/blob/main/docs/usage.md#conversion))
- Extra utilities such as ([`:Abs()` `:Min()` `:Max()`](https://github.com/fosterchild1/AptInt/blob/main/docs/usage.md#extensions))

The implementations are as performant as possible, so they have no safety checks, with the exception of the metamethods.

# Usage
Usage Documentation can be found [here](https://github.com/fosterchild1/AptInt/blob/main/docs/usage.md).<br/>
Algorithm choice can be found [here](https://github.com/fosterchild1/AptInt/blob/main/docs/algorithms.md).

# What makes it so fast?
AptInt uses many asymptotically fast algorithms and dispatches between them based on input size. Alongside this, tables are recycled to their fullest potential, bringing the allocation count low. It also utilizes the full power of native code generation. This makes real use be very fast.

# Benchmarks

Note that these were done on a Ryze 9 8940HX CPU @ 4.5GHz. The benchmark script can be found in [/bench/](https://github.com/fosterchild1/AptInt/blob/main/bench/bench.luau).<br/>
The results are updated every time the performance gets improved.
For division, we do a 2NxN division. (2N = digit count)

### Raw
| Digit count | Addition | Subtraction | Multiplication | Division | Square root |
| ---  | --- | --- | --- | --- | --- |
| 1 | 27ns | 20ns | 158ns | 105ns | 9μs |
| 50 | 400ns | 600ns | 476ns | 846ns | 27μs |
| 100 | 500ns | 700ns | 1μs | 2μs | 73μs |
| 500 | 2μs | 1μs | 23μs | 14μs | 143μs |
| 1,000 | 3μs | 3μs | 111μs | 47μs | 299μs |
| 5,000 | 11μs | 18μs | 1ms | 195μs | 796μs |
| 10,000 | 21μs | 24μs | 3ms | 1ms | 2ms |
| 50,000 | 102μs | 222μs | 46ms | 38ms | 28ms |
| 100,000 | 387μs | 310μs | 122ms | 114ms | 87ms |
