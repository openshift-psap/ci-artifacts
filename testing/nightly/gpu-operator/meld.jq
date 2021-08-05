# recursively combines two composite JSON entities by concatenating arrays at the same position
# taken from https://stackoverflow.com/a/53666584/791430
def meld(a; b):
  a as $a | b as $b
  | if ($a|type) == "object" and ($b|type) == "object"
    then reduce ([$a,$b]|add|keys_unsorted[]) as $k ({}; 
      .[$k] = meld( $a[$k]; $b[$k]) )
    elif ($a|type) == "array" and ($b|type) == "array"
    then $a+$b
    elif $b == null then $a
    else $b
    end;

