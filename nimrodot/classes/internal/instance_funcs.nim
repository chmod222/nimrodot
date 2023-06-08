import std/typetraits

import ../../utils
import ../../ffi
import ../../interface_ptrs

export ffi
export utils

proc makeInstanceFunctions*[T](_: typedesc[T]): GDExtensionInstanceBindingCallbacks =
  type
    TObj = pointerBase T

  proc create_callback(token, instance: pointer): pointer {.cdecl.} =
    result = gdInterfacePtr.mem_alloc(csize_t sizeOf(`TObj`))

    cast[T](result)[] = `TObj`(opaque: instance, vtable: T.gdVTablePointer())

  proc free_callback(token, instance, binding: pointer) {.cdecl.} =
    gdInterfacePtr.mem_free(binding)

  proc reference_callback(token, instance: pointer; reference: GDExtensionBool): GDExtensionBool {.cdecl.} =
    1

  GDExtensionInstanceBindingCallbacks(
    create_callback: create_callback,
    free_callback: free_callback,
    reference_callback: reference_callback)