# This is a very boilerplatey part that would poison the readability of the
# classdb module, so we yank it in.

# Generic helpers
macro procArgsUnnamed(p: typed; skipVar: static[bool] = true): typedesc =
  ## Given a proc type, generate an unnamed tuple where each element
  ## corresponds to an argument.
  let procType = p.getTypeImpl()

  procType.expectKind(nnkProcTy)

  result = nnkTupleConstr.newTree()

  for arg in procType[0][1..^1]:
    if arg[1].kind == nnkVarTy and skipVar: continue

    result &= arg[1]

macro procArgs(p: typed; skipVar: static[bool] = true): typedesc =
  ## Given a proc type, generate a tuple where each element
  ## corresponds to an argument with that name.
  let procType = p.getTypeImpl()

  procType.expectKind(nnkProcTy)

  result = nnkTupleTy.newTree()

  for arg in procType[0][1..^1]:
    if arg[1].kind == nnkVarTy and skipVar: continue

    result &= newIdentDefs(
      newTree(nnkAccQuoted, arg[0]),
      arg[1],
      newEmptyNode())

macro procReturn(p: typed): typedesc =
  ## Given a proc type, return its return type (or typedesc[void])
  let procType = p.getTypeImpl()

  procType.expectKind(nnkProcTy)

  if procType[0][0].kind == nnkEmpty:
    genAst: void
  else:
    genAst(R = procType[0][0]): R

macro procArity(p: typed; skipVar: static[bool] = true): auto =
  ## Given a proc type, return its arity
  let procType = p.getTypeImpl()

  procType.expectKind(nnkProcTy)

  var minArgc = 0
  var variadic = false

  for arg in procType[0][1..^1]:
    if arg[1].kind == nnkVarTy and skipVar: continue
    if arg[1].kind == nnkBracketExpr and arg[1][0].strVal() == "varargs":
      variadic = true

      break

    inc minArgc

  genAst(minArgc, isVar = variadic):
    (argCount: minArgc, variadic: isvar)

macro apply(fn, args: typed): auto =
  ## Given a callable and a (named or unnamed) tuple of its arguments,
  ## invoke the callable with the given arguments.
  result = newTree(nnkCall, fn)

  for arg in args:
    result.add(if arg.kind == nnkExprColonExpr: arg[1] else: arg)


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

# TODO: We need some more complex type converters. For most of these we can
#       simply blit over whatever Godot gives us, but for things like Ref[T]
#       we need to may need to use ref_get_object and ref_set_object.
func argFromPointer[T](p: GDExtensionConstTypePtr): T =
  copyMem(addr result, p, sizeOf(T))