import ../nodot
import ./ffi
import ./builtins/types/[stringname, "string"]

# N.B. I'm not particularly happy with this module, but for now I see
#      not better way. All these functions are technically already exposed
#      through the proper bindings (safe for "string_new_with_utf8_chars")
#      but we cannot use them as we need to be able to construct StringNames
#      to fetch methods, properties and consts but the functions to do so need
#      to be visibile in every generated module (including String and StringName)
#      leading to cyclic dependencies unless we split the modules even more fine
#      grade, which hurts maintainability in the long run.

proc stringToStringName(str: String): StringName =
  var ctor {.global.} =                            # let's hope this doesn't change  v
    gdInterfacePtr.variant_get_ptr_constructor(GDEXTENSION_VARIANT_TYPE_STRING_NAME, 2)

  var args = [unsafeAddr str]

  ctor(cast[GDExtensionTypePtr](addr result), cast[ptr GDExtensionConstTypePtr](addr args))

proc destroyString*(str: sink String) =
  var dtor {.global.} =
    gdInterfacePtr.variant_get_ptr_destructor(GDEXTENSION_VARIANT_TYPE_STRING)

  dtor(unsafeAddr str)

proc destroyStringName*(str: sink StringName) =
  var dtor {.global.} =
    gdInterfacePtr.variant_get_ptr_destructor(GDEXTENSION_VARIANT_TYPE_STRING_NAME)

  dtor(unsafeAddr str)

proc toGodotStringName*(native: string): StringName =
  var interm: String = default(String)

  gdInterfacePtr.string_new_with_utf8_chars(addr interm, cstring(native))
  result = stringToStringName(interm)

  destroyString interm

