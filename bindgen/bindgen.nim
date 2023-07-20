import std/[os, options, sets]

import ./api
import ./helpers

const sourceApiFile = "contrib/extension_api.json"

import filters/files/"api.nimf" as apiFileGen
import filters/files/"utility.nimf" as utilityFileGen
import filters/files/"native_structs.nimf" as nativeStructsFileGen
import filters/files/"enums.nimf" as enumsFileGen
import filters/files/builtins/"all_types.nimf" as builtinAllTypesGen
import filters/files/builtins/"type.nimf" as builtinTypeGen
import filters/files/builtins/"procs.nimf" as builtinProcGen
import filters/files/classes/"type.nimf" as classTypeGen
import filters/files/classes/"procs.nimf" as classProcGen

when nimvm:
  func projectPath(): string = "./bindgen/bindgen.nim"

  proc rmFile(path: string) =
    path.removeFile()

  proc cpFile(source, dest: string) =
    source.copyFile(dest)

  proc mkDir(dirs: string) =
    dirs.createDir()

else:
  discard

when isMainModule:
  echo projectPath()

  let projectRoot = projectPath()
    .parentDir()
    .parentDir()

  let sourceRoot = projectRoot / "nimrodot"
  let apiFile = sourceApiFile.importApi()

  # cpFile(projectRoot / "contrib/gdextension_interface.nim", sourceRoot  / "ffi.nim")

  helpers.apiDef = apiFile

  writeFile(sourceRoot / "api.nim", apiFileGen.generate())
  writeFile(sourceRoot / "utility_functions.nim", utilityFileGen.generate())
  writeFile(sourceRoot / "enums.nim", enumsFileGen.generate())
  writeFile(sourceRoot / "native_structs.nim", nativeStructsFileGen.generate())

  mkdir sourceRoot / "builtins" / "types"
  mkdir sourceRoot / "classes" / "types"

  writeFile(
    sourceRoot / "builtins" / "types.nim",
    builtinAllTypesGen.generate())

  for builtinClass in apiFile.builtin_classes:
    if not builtinClass.isNativeClass():
      writeFile(
        sourceRoot / "builtins" / "types" / builtinClass.moduleName() & ".nim",
        builtinTypeGen.generate(builtinClass))

      writeFile(
        sourceRoot / "builtins" / builtinClass.moduleName() & ".nim",
        builtinProcGen.generate(builtinClass))

  # We want to generate the classes in the correct topological order as
  # determined by inheritance, starting at "Object"
  var remainingClasses = apiFile.classes

  var sortedClasses = newSeq[ClassDefinition]()
  var openParentClasses = newSeq[ClassDefinition]()
  var resolved = initHashSet[string]()

  # Need object first
  for cls in apiFile.classes:
    if cls.inherits.isNone:
      openParentClasses &= cls
      resolved.incl cls.name

      break

  while len(openParentClasses) > 0:
    sortedClasses &= openParentClasses.pop()

    let parentName = sortedClasses[^1].name

    for cls in remainingClasses:
      if cls.name notin resolved and
          cls.inherits.isSome() and
          cls.inherits.unsafeGet() == parentName:

        resolved.incl cls.name
        openParentClasses &= cls

  for class in sortedClasses:
    writeFile(
      sourceRoot / "classes" / "types" / class.moduleName() & ".nim",
      classTypeGen.generate(class))

    writeFile(
      sourceRoot / "classes" / class.moduleName() & ".nim",
      classProcGen.generate(class))