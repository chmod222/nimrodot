import std/macros

proc NimMain() {.cdecl, importc.}

import nodot/ffi
import nodot/interface_ptrs
import nodot/ref_helper
import nodot/classes/types/"object"
import nodot/utils

export ref_helper
export ffi
export interface_ptrs
export utils

proc getSingleton*[T: Object](name: string): T =
  var name = &name

  T(opaque: gdInterfacePtr.global_get_singleton(addr name))

macro godotHooks*(
    name: static[string];
    level: static[GDExtensionInitializationLevel];
    def: untyped) =

  let initIdent = name.ident()
  let globIdentIf = "gdInterfacePtr".ident()
  let globIdentTk = "gdTokenPtr".ident()

  def.expectKind(nnkStmtList)
  def[0].expectKind(nnkCall)
  def[1].expectKind(nnkCall)

  def[0][0].expectIdent("initialize")
  def[1][0].expectIdent("deinitialize")

  let initLevelParam = def[0][1]
  let initBody = def[0][2]

  let deinitLevelParam = def[1][1]
  let deinitBody = def[1][2]

  result = quote do:
    proc gdInit(userdata: pointer; `initLevelParam`: GDExtensionInitializationLevel) {.cdecl.} =
      `initBody`

    proc gdDeinit(userdata: pointer; `deinitLevelParam`: GDExtensionInitializationLevel) {.cdecl.} =
      `deinitBody`

    proc `initIdent`*(
        interf: ptr GDExtensionInterface;
        library: GDExtensionClassLibraryPtr;
        init: ptr GDExtensionInitialization): GDExtensionBool {.exportc, dynlib, cdecl.} =

      `globIdentIf` = interf
      `globIdentTk` = library

      NimMain()

      init.minimum_initialization_level = GDExtensionInitializationLevel(`level`)
      init.initialize = gdInit
      init.deinitialize = gdDeinit

      result = 1

template godotHooks*(name: static[string]; def: untyped) =
  godotHooks(name, GDEXTENSION_MAX_INITIALIZATION_LEVEL, def)

template godotHooks*(level: static[GDExtensionInitializationLevel]; def: untyped) =
  godotHooks("gdext_init", level, def)

template godotHooks*(def: untyped) =
  godotHooks("gdext_init", GDEXTENSION_MAX_INITIALIZATION_LEVEL, def)

