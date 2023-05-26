import std/genasts
import ../nodot

macro generateBuiltinHooks*(T: typedesc; copyCtorIdx: static[int]) =
  result = genAst(T, copyCtorIdx):
    proc `=copy`*(a: var T; b: T) =
      var copyCtor {.global.} = gdInterfacePtr.variant_get_ptr_constructor(
        T.variantTypeId, copyCtorIdx)

      let args: array[1, GDExtensionConstTypePtr] = [
        cast[GDExtensionConstTypePtr](unsafeAddr b)
      ]

      copyCtor(addr a, cast[ptr GDExtensionConstTypePtr](unsafeAddr args))

    proc `=destroy`*(st: var T) =
      var p {.global.} = gdInterfacePtr.variant_get_ptr_destructor(
        T.variantTypeId)

      p(cast[GDExtensionTypePtr](addr st))