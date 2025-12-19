<p align="center"><img src="https://github.com/fosterchild1/AptInt/blob/main/resources/text.png" width="659" height="288"></p>

# Luau implementation of BigInteger.
It can go up to <b>b*2^53 digits</b> before it starts losing precision. Currently, b is equal to 10^7. (that's 90 sextillion digits!)

# Extensions
Extending the module is very easy. Just call `AptInt.Extend(func: typeof(BigInteger) -> ())`. For example,

```luau
AptInt.Extend(function(tbl: typeof(AptInt) | any)
	function tbl:IsEven(): boolean
		return (self :: AptInt).digits[1] % 2 == 0
	end
end)
```
