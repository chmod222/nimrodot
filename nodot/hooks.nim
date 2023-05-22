import std/[genasts, typetraits]
import ../nodot

macro generateHooks*(T: typedesc, isRefcounted, isSingleton: static[bool]) =
  let typeName = T

  if isRefcounted:
    result = genAst(typeName):
      proc `=destroy`*(st: var typeName) =
        gdInterfacePtr.object_destroy(st.opaque)

      proc `=copy`*(a: var typeName; b: typeName) =
        discard
  else:
    result = genAst(typeName, isSingleton):
      proc `=destroy`*(st: var typeName) =
        when not isSingleton:
          gdInterfacePtr.object_destroy(st.opaque)

      proc `=sink`(dest: var typeName; source: typeName) =
        wasMoved(dest)

        dest.opaque = source.opaque

      proc `=copy`*(a: var typeName; b: typeName)
        {.error.}

  echo result.repr()