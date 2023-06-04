# This is a very boilerplatey part that would poison the readability of the
# classdb module, so we yank it in.

# Generic helpers
macro procReturn(p: typed): typedesc =
  ## Given a proc type, return its return type (or typedesc[void])
  let procType = p.getTypeImpl()

  procType.expectKind(nnkProcTy)

  if procType[0][0].kind == nnkEmpty:
    genAst: void
  else:
    genAst(R = procType[0][0]): R

macro procArity(p: typed; isStatic: static[bool]): auto =
  ## Given a proc type, return its arity
  let procType = p.getTypeImpl()

  procType.expectKind(nnkProcTy)

  var minArgc = 0
  var variadic = false

  for arg in procType[0][1..^1]:
    if arg[1].kind == nnkBracketExpr and arg[1][0].strVal() == "varargs":
      variadic = true

      break

    inc minArgc

  if not isStatic:
    dec minArgc

  genAst(minArgc, isVar = variadic):
    (argCount: minArgc, variadic: isvar)

# Property Helpers
func propertyHint(_: typedesc): auto = phiNone
func propertyUsage(_: typedesc): auto = pufDefault
func propertyUsage(_: typedesc[Variant]): auto = ord(pufDefault) or ord(pufNilIsVariant)

# Type Metadata Helpers
func typeMetaData(_: typedesc): auto = GDEXTENSION_METHOD_ARGUMENT_METADATA_NONE
func typeMetaData(_: typedesc[int8]): auto = GDEXTENSION_METHOD_ARGUMENT_METADATA_INT_IS_INT8
func typeMetaData(_: typedesc[int16]): auto = GDEXTENSION_METHOD_ARGUMENT_METADATA_INT_IS_INT16
func typeMetaData(_: typedesc[int32]): auto = GDEXTENSION_METHOD_ARGUMENT_METADATA_INT_IS_INT32
func typeMetaData(_: typedesc[int64]): auto = GDEXTENSION_METHOD_ARGUMENT_METADATA_INT_IS_INT64
func typeMetaData(_: typedesc[uint8]): auto = GDEXTENSION_METHOD_ARGUMENT_METADATA_INT_IS_UINT8
func typeMetaData(_: typedesc[uint16]): auto = GDEXTENSION_METHOD_ARGUMENT_METADATA_INT_IS_UINT16
func typeMetaData(_: typedesc[uint32]): auto = GDEXTENSION_METHOD_ARGUMENT_METADATA_INT_IS_UINT32
func typeMetaData(_: typedesc[uint64]): auto = GDEXTENSION_METHOD_ARGUMENT_METADATA_INT_IS_UINT64
func typeMetaData(_: typedesc[float32]): auto = GDEXTENSION_METHOD_ARGUMENT_METADATA_REAL_IS_FLOAT
func typeMetaData(_: typedesc[float64 | float]): auto = GDEXTENSION_METHOD_ARGUMENT_METADATA_REAL_IS_DOUBLE

func typeMetaData(_: typedesc[int | uint]): auto =
  if (sizeOf int) == 4:
    GDEXTENSION_METHOD_ARGUMENT_METADATA_INT_IS_INT32
  else:
    GDEXTENSION_METHOD_ARGUMENT_METADATA_INT_IS_INT64

# isVarArg and getProcProps are used registerMethod in order to collect all
# the information Godot wants out of the to be registered funtion pointer.
func isVarArg(m: NimNode): bool =
  result = m.kind == nnkBracketExpr and m[0].strVal() == "varargs"

func isSelf(ft: NimNode; T: NimNode): bool =
  T.getTypeInst()[1] == ft

macro isStatic(M: typed; T: typedesc): bool =
  let procDef = M.getType()[1].getTypeImpl()[0]

  var isStatic = true

  if len(procDef) > 1:
    isStatic = not procDef[1][^2].isSelf(T)

  genAst(isStatic):
    isStatic

macro getProcProps(M: typed; T: typedesc): auto =
  let procDef = M.getType()[1].getTypeImpl()[0]

  var argc = 0

  var args = newTree(nnkBracket)
  var argsMeta = newTree(nnkBracket)
  var isStatic = true
  var isVararg = false
  var procFlags = newTree(nnkCurly, ident"GDEXTENSION_METHOD_FLAGS_DEFAULT")

  let rval = if procDef[0].kind == nnkEmpty:
    genAst() do:
      none (GDExtensionPropertyInfo, GDExtensionClassMethodArgumentMetadata)
  else:
    genAst(R = procDef[0]) do:
      some (
        GDExtensionPropertyInfo(
          `type`: variantTypeId(typeOf R),
          name: staticStringName(""),
          class_name: gdClassName(typeOf R),
          hint: uint32(propertyHint(typeOf R)),
          hint_string: staticStringName(""),
          usage: uint32(propertyUsage(typeOf R))),
        typeMetaData(typeOf R))

  if len(procDef) > 1:
    let offset = if procDef[1][^2].isSelf(T): 2 else: 1

    isStatic = offset == 1

    for defs in procDef[offset..^1]:
      for binding in defs[0..^3]:
        if defs[^2].isVarArg:
          isVararg = true

          break

        inc argc

        let argMeta = genAst(P = defs[^2]):
          typeMetaData(typeOf P)

        let arg = genAst(n = binding.strVal(), P = defs[^2]):
          GDExtensionPropertyInfo(
           `type`: variantTypeId(typeOf P),
            name: staticStringName(n),
            class_name: gdClassName(typeOf P),
            hint: uint32(propertyHint(typeOf P)),
            hint_string: staticStringName(""),
            usage: uint32(propertyUsage(typeOf P))
          )

        argsMeta &= argMeta
        args &= arg

  if isStatic: procFlags &= ident"GDEXTENSION_METHOD_FLAG_STATIC"
  if isVararg: procFlags &= ident"GDEXTENSION_METHOD_FLAG_VARARG"

  result = genAst(procArgc = argc, isStatic, procArgs = args, procArgsMeta = argsMeta, procFlags, rval):
    tuple[pargc: int,
          pargs: array[procArgc, GDExtensionPropertyInfo],
          pmeta: array[procArgc, GDExtensionClassMethodArgumentMetadata],
          retval: Option[(GDExtensionPropertyInfo, GDExtensionClassMethodArgumentMetadata)],
          pflags: system.set[GDExtensionClassMethodFlags]](
      pargc: procArgc,
      pargs: procArgs,
      pmeta: procArgsMeta,
      retval:  rval,
      pflags: procFlags)