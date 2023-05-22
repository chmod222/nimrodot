import std/[genasts, typetraits]
import ../nodot

macro generateHooks*(T: typedesc, isRefcounted: static[bool]) =
  if isRefcounted:
    result = genAst(T):
      import nodot/classes/refcounted

      proc `=copy`*(a: var T; b: T) =
        discard a.reference()

        a.opaque = b.opaque

      proc `=destroy`*(st: var T) =
        discard st.unreference()

        if st.get_reference_count() == 0:
          gdInterfacePtr.object_destroy(st.opaque)
  else:
    result = genAst(T):
      proc `=destroy`*(st: var T) =
        gdInterfacePtr.object_destroy(st.opaque)

      proc `=sink`(dest: var T; source: T) =
        wasMoved(dest)

        dest.opaque = source.opaque

      proc `=copy`*(a: var T; b: T)
        {.error.}