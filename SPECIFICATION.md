# Version v1.0-alpha5

### Value

```
value ::=
      \x00            # null
    | \x01            # true
    | \x02            # false
    | \x03 number
    | \x05 string
    | \x09 array
    | \x0A object
    | \b1???????      # deleted

number              ::= number_length json_number_string

number_length       ::= uint8

string              ::= string_length json_encoded_string

string_length       ::= uint32
```

### Array

```
array         ::= array_length elements

array_length  ::= uint32                # size of elements

elements
      element elements
    | < empty >
```

### Object

```
object        ::= object_length key_value_pairs

object_length ::= uint32               # size of key_value_pairs
 
key_value_pairs
      key value key_value_pairs
    | < empty >

key           ::= key_length json_encoded_string

key_length    ::= uint8
```
