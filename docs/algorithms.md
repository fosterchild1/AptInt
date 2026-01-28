This library uses many algorithms to speed up expensive operations such as exponentiation or division. Below is a list of all algorithms used.

In the computational complexity, we use a couple of terms that may be unknown to some. Their meanings are listed below:
- n - the size of the input, in limbs
- m - size of secondary input, also in limbs
  
### Addition and subtraction
No algorithms used.<br/>
- Average case: O(min(n, m))
- Worst case: O(max(n, m))

### Multiplication
3 algorithms are used to multiply:
- Basecase multiplication: diagonal-based O(n^2) multiplication.
- Karatsuba multiplication: For n,m > `KARATSUBA_THRESHOLD`, O(n^1.565) [Karatsuba algorithm](https://en.wikipedia.org/wiki/Karatsuba_algorithm) is used.
- Toom Cook-3 multiplication: For n,m > `TOOM_THRESHOLD`, O(n^1.464) [Toom-3 multiplication](https://en.wikipedia.org/wiki/Toom%E2%80%93Cook_multiplication) is used.
   - Toom-1.5 multiplication was considered due to the amount of time Basecase multiplication takes, but it was deemed too slow.

### Division
2 algorithms are used to divide:
- Basecase division: O(n^2) [Knuths division](https://skanthak.hier-im-netz.de/division.html).
- Burnikel-Ziegler division: For n,m > `BURNIKEL_THRESHOLD`, O(n log n) [Burnikel-Ziegler division](https://pure.mpg.de/rest/items/item_1819444_4/component/file_2599480/content) is used.

### Exponentiation
Exponentiation uses O(n log n) [exponentiation by squaring](https://en.wikipedia.org/wiki/Exponentiation_by_squaring).

### Square root
2 algorithms are used to find the square root:
- Basecase sqrt: O(n^2 log n) [Newton-Heron](https://en.wikipedia.org/wiki/Integer_square_root#Algorithm_using_Newton's_method) square root.
- Karatsuba sqrt: For n,m > `SQRT_KARATSUBA_THRESHOLD`, runs [Karatsuba sqrt](https://inria.hal.science/inria-00072854v1/file/RR-3805.pdf) in M(n) time, where M(n) = time to multiply two n-sized numbers.
   - Binary search was considered, but it was deemed too slow.
