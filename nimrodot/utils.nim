import ./interface_ptrs
import ./ffi

import ./builtins/types/["string", stringname]

# Use Godot's "StringName(String)" constructor.
proc stringToStringName(str: String): StringName =
  var ctor {.global.} =                            # let's hope this doesn't change  v
    gdInterfacePtr.variant_get_ptr_constructor(GDEXTENSION_VARIANT_TYPE_STRING_NAME, 2)

  var args = [unsafeAddr str]

  ctor(cast[GDExtensionTypePtr](addr result), cast[ptr GDExtensionConstTypePtr](addr args))


proc `$`*(str: String): string =
  let strLen = gdInterfacePtr.string_to_utf8_chars(unsafeAddr str, nil, 0)
  result = newString(strLen)

  if strLen > 0:
    discard gdInterfacePtr.string_to_utf8_chars(
      unsafeAddr str,
      cast[cstring](addr result[0]),
      strLen)

proc newString*(native: string): String =
  gdInterfacePtr.string_new_with_utf8_chars(addr result, cstring(native))

proc newStringName*(native: string): StringName =
  var interm = newString(native)

  gdInterfacePtr.string_new_with_utf8_chars(addr interm, cstring(native))
  result = stringToStringName(interm)


converter toStringName*(src: string): StringName =
  newStringName(src)

converter toString*(src: string): String =
  newString(src)

# Convenience converter that mirrors Godot's syntax.
template `&`*(native: string): StringName =
  newStringName(native)

# TODO: For all variants, add `$` with variant -> str conversion