import ../nodot
import ./ffi
import ./builtins/types/[stringname, "string"]

import std/[macros, typetraits]

proc stringToStringName(str: String): StringName =
  var ctor {.global.} =                            # let's hope this doesn't change  v
    gdInterfacePtr.variant_get_ptr_constructor(GDEXTENSION_VARIANT_TYPE_STRING_NAME, 2)

  var args = [unsafeAddr str]

  ctor(cast[GDExtensionTypePtr](addr result), cast[ptr GDExtensionConstTypePtr](addr args))

proc toGodotStringName*(native: string): StringName =
  var interm: String = default(String)

  gdInterfacePtr.string_new_with_utf8_chars(addr interm, cstring(native))
  result = stringToStringName(interm)


