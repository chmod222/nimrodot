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


proc makeInstanceFunctions*[T](_: typedesc[T]): GDExtensionInstanceBindingCallbacks =
  type
    TObj = pointerBase T

  proc create_callback(token, instance: pointer): pointer {.cdecl.} =
    result = gdInterfacePtr.mem_alloc(csize_t sizeOf(`TObj`))

    cast[T](result)[] = `TObj`(opaque: instance)

  proc free_callback(token, instance, binding: pointer) {.cdecl.} =
    gdInterfacePtr.mem_free(instance)

  proc reference_callback(token, instance: pointer; reference: GDExtensionBool): GDExtensionBool {.cdecl.} =
    1

  GDExtensionInstanceBindingCallbacks(
    create_callback: create_callback,
    free_callback: free_callback,
    reference_callback: reference_callback)