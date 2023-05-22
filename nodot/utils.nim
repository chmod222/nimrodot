import ./builtins/types/"string"
import ../nodot

proc `$`*(str: String): string =
  let strLen = gdInterfacePtr.string_to_utf8_chars(unsafeAddr str, nil, 0)
  result = newString(strLen)

  discard gdInterfacePtr.string_to_utf8_chars(
    unsafeAddr str,
    cast[cstring](addr result[0]),
    strLen)

proc newString*(native: string): String =
  gdInterfacePtr.string_new_with_utf8_chars(addr result, cstring(native))

# TODO: For all variants, add `$` with variant -> str conversion