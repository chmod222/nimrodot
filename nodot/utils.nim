import ./interface_ptrs
import ./ffi

import ./builtins/types/["string", stringname]


proc `$`*(str: String): string =
  let strLen = gdInterfacePtr.string_to_utf8_chars(unsafeAddr str, nil, 0)
  result = newString(strLen)

  discard gdInterfacePtr.string_to_utf8_chars(
    unsafeAddr str,
    cast[cstring](addr result[0]),
    strLen)

proc newString*(native: string): String =
  gdInterfacePtr.string_new_with_utf8_chars(addr result, cstring(native))

proc stringToStringName(str: String): StringName =
  var ctor {.global.} =                            # let's hope this doesn't change  v
    gdInterfacePtr.variant_get_ptr_constructor(GDEXTENSION_VARIANT_TYPE_STRING_NAME, 2)

  var args = [unsafeAddr str]

  ctor(cast[GDExtensionTypePtr](addr result), cast[ptr GDExtensionConstTypePtr](addr args))

proc toGodotString*(native: string): String =
  gdInterfacePtr.string_new_with_utf8_chars(addr result, cstring(native))

proc toGodotStringName*(native: string): StringName =
  var interm = native.toGodotString()

  gdInterfacePtr.string_new_with_utf8_chars(addr interm, cstring(native))
  result = stringToStringName(interm)


converter toStringName*(src: string): StringName =
  src.toGodotStringName

converter toString*(src: string): String =
  src.toGodotString

# TODO: For all variants, add `$` with variant -> str conversion