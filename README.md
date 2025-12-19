<img src="https://github.com/fosterchild1/AptInt/blob/main/resources/text.png"> </br>
# <p align="center">Luau implementation of BigInteger.</p>
<p align="center">It can go up to <b>b*2^53 digits</b> before it starts losing precision. Currently, b is equal to 10^7. (that's 90 sextillion digits!)</p>

# <p align="center">Extensions</p>
<p align="center">Extending the module is very easy. Just call `AptInt.Extend(func: typeof(BigInteger) -> ())`. For example,</p>
<br/>

```luau
AptInt.Extend(function(tbl: typeof(AptInt) | any)
	function tbl:IsEven(): boolean
		return (self :: AptInt).digits[1] % 2 == 0
	end
end)
```
