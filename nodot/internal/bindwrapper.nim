type
  CallMarshallingError = object of CatchableError
    argument: int32
    expected: int32

proc raiseArgError(argpos: int32, expectedType: GDExtensionVariantType) =
  var err = newException(CallMarshallingError, "")

  err.argument = argpos
  err.expected = expectedType.int32

  raise err

proc tryCastTo*[T](arg: Variant; _: typedesc[T]; argPos: var int32): T =
  try:
    result = arg.castTo(T)
  except VariantCastException:
    raiseArgError(argPos, T.variantTypeId)

  inc argPos

# TODO: We need some more complex type converters. For most of these we can
#       simply blit over whatever Godot gives us, but for things like Ref[T]
#       we need to may need to use ref_get_object and ref_set_object.
func argFromPointer[T](p: GDExtensionConstTypePtr): T =
  copyMem(addr result, p, sizeOf(T))

# Call a function with a number of Variant pointers (bindcall)
macro callBindFunc(
    def: typed;
    argsArray: ptr UncheckedArray[ptr Variant];
    argc: typed;
    argPos: int32;
    self: typed = nil): auto =
  let typedFunc = def.getTypeInst()[0]

  var argsStart = 1

  result = newTree(nnkCall, def)

  if len(typedFunc) > 1:
    if self.kind != nnkNilLit:
      result &= newTree(nnkBracketExpr, self)

      inc argsStart

    for i, arg in enumerate(typedFunc[argsStart..^1]):
      if arg[^2].isVarArg():
        # If we hit a varargs[T] parameter, generate a preamble statement to fill a seq[]
        # and wrap our original result into a block statement.
        let varArgsId = genSym(nskVar, "vargs")

        result.add varArgsId

        return genAst(T = arg[^2][1], start = i, argsArray, argc, varArgsId, doCall = result) do:
          block:
            var varArgsId = newSeqOfCap[typeOf T](argc - start)

            for i in start .. argc - 1:
                varArgsId &= maybeDowncast[T](argsArray[i][].tryCastTo(mapBuiltinType(typeOf T), argPos))
                inc argPos

            doCall

      result.add genAst(T = arg[^2], argsArray, i) do:
        maybeDowncast[T](argsArray[i][].tryCastTo(mapBuiltinType(typeOf T), argPos))

# Call a function with a number of builtin pointers (ptrcall)
#
# This is highly unsafe of course, but at this point we have to trust Godot not
# to send us bad data. If it does, we do the same thing it does when we do that:
# crash.
func stuffArguments(
    call: NimNode;
    typedFunc: NimNode;
    offset: static[int];
    argsArray: NimNode) =

  for i, arg in enumerate(typedFunc[offset..^1]):
    let argBody = if arg[^2].isVarArg():
      # Cannot be done using ptrcall, so we leave it empty in case
      # a vararg function is ever called using ptrcall.
      break
    else:
      genAst(T = arg[^2], argsArray, i):
        maybeDowncast[T](argFromPointer[mapBuiltinType(typeOf T)](argsArray[i]))

    call &= argBody

macro callPtrFunc(
    def: typed;
    self: typed;
    argsArray: ptr UncheckedArray[GDExtensionConstTypePtr]): auto =
  let typedFunc = def.getTypeInst()[0]

  result = newTree(nnkCall, def)

  if len(typedFunc) > 1:
    # In case our receiver func takes a parent object of T, we cast it.
    result &= newTree(nnkCast, typedFunc[1][^2], self)
    result.stuffArguments(typedFunc, 2, argsArray)

macro callPtrFunc(
    def: typed;
    argsArray: ptr UncheckedArray[GDExtensionConstTypePtr]): auto =
  let typedFunc = def.getTypeInst()[0]

  result = newTree(nnkCall, def)

  if len(typedFunc) > 1:
    result.stuffArguments(typedFunc, 1, argsArray)

proc invoke_ptrcall[T](
    callable: auto;
    isStatic: static[bool];
    instance: GDExtensionClassInstancePtr;
    args: ptr GDExtensionConstTypePtr;
    returnPtr: GDExtensionTypePtr) {.cdecl.} =

  let argArray = cast[ptr UncheckedArray[GDExtensionConstTypePtr]](args)

  type R = callable.procReturn()

  # Ugly double duplication here, sorry.
  when isStatic:
    when R is void:
      callable.callPtrFunc(argArray)
    else:
      cast[ptr mapBuiltinType(typeOf R)](returnPtr)[] = callable.callPtrFunc(argArray)
  else:
    let nimInst = cast[ptr T](instance)

    when R is void:
      callable.callPtrFunc(nimInst, argArray)
    else:
      cast[ptr mapBuiltinType(typeOf R)](returnPtr)[] = callable.callPtrFunc(nimInst, argArray)

proc invoke_bindcall[T](callable: auto;
                        isStatic: static[bool];
                        instance: GDExtensionClassInstancePtr;
                        args: ptr GDExtensionConstVariantPtr;
                        argc: GDExtensionInt;
                        ret: GDExtensionVariantPtr;
                        error: ptr GDExtensionCallError) {.cdecl.} =

  let argArray = cast[ptr UncheckedArray[ptr Variant]](args)
  var argPos = 0'i32

  type
    R = callable.procReturn()

  const arity = callable.procArity(isStatic)

  if argc < arity.argCount:
    error[].error = GDEXTENSION_CALL_ERROR_TOO_FEW_ARGUMENTS
    error[].argument = int32(arity.argCount)
    error[].expected = int32(arity.argCount)

    return
  elif argc > arity.argCount and not arity.variadic:
    error[].error = GDEXTENSION_CALL_ERROR_TOO_MANY_ARGUMENTS
    error[].argument = int32(arity.argCount)
    error[].expected = int32(arity.argCount)

    return

  error[].error = GDEXTENSION_CALL_OK

  try:
    # Yet more ugly double duplication here.
    when isStatic:
      when R is void:
        callable.callBindFunc(argArray, argc, argPos)
      else:
        let returnValue = cast[ptr Variant](ret)

        returnValue[] = %maybeDowncast[mapBuiltinType R](callable.callBindFunc(argArray, argc, argPos))
    else:
      let nimInst = cast[ptr T](instance)

      when R is void:
        callable.callBindFunc(argArray, argc, argPos, nimInst)
      else:
        let returnValue = cast[ptr Variant](ret)

        returnValue[] = %maybeDowncast[mapBuiltinType R](callable.callBindFunc(argArray, argc, argPos, nimInst))

  except CallMarshallingError as cme:
    error[].error = GDEXTENSION_CALL_ERROR_INVALID_ARGUMENT
    error[].argument = cme.argument
    error[].expected = cme.expected

  except CatchableError:
    # For the lack of a better option
    error[].error = GDEXTENSION_CALL_ERROR_INVALID_METHOD
