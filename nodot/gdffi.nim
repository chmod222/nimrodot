import std/[macros, genasts, options]

import ./interface_ptrs
import ./ffi
import ./utils

import ./builtins/variant
import ./builtins/types

import ./classes/types/"object"

export utils.toGodotStringName

type
  ReturnInfo = object
    isVoid: bool

    fullType: NimNode

  ParamInfo = object
    isStatic: bool

    fullType: NimNode
    binding: NimNode

func resolveReturn(prototype: NimNode): ReturnInfo =
  if prototype[3][0].kind == nnkEmpty:
    result.isVoid = true
  else:
    result.fullType = prototype[3][0]

func resolveSelf(prototype: NimNode): ParamInfo =
  if len(prototype[3]) > 1 and prototype[3][1][0] == "_".ident():
    result.fullType = prototype[3][1][1][1]
    result.isStatic = true
  else:
    result.isStatic = false
    result.binding = prototype[3][1][0]

    if prototype[3][1][^2].kind == nnkVarTy:
      result.fullType = prototype[3][1][1][0]
    else:
      result.fullType = prototype[3][1][1]

func isRefCountWrapper(s: ParamInfo | ReturnInfo): bool =
  s.fullType.kind == nnkBracketExpr and s.fullType[0].strVal == "Ref"

func reduceType(s: ParamInfo | ReturnInfo): NimNode =
  if s.fullType.kind == nnkBracketExpr:
    s.fullType[1]
  else:
    s.fullType

func reducePtr(s: ParamInfo): NimNode =
  if s.isStatic:
    # Static methods take a nil pointer
    newNilLit()
  elif s.isRefCountWrapper:
    # Ref[T] wrappers reduce to self[].opaque
    newDotExpr(newTree(nnkBracketExpr, s.binding), "opaque".ident())
  else:
    # Everything else reduces to self.opaque
    newDotExpr(s.binding, "opaque".ident())

func reducePtr(r: ReturnInfo): NimNode =
  if r.isVoid:
    # No result pointer for void procs
    newNilLit()
  else:
    # We delegate to the nim compiler via template because we need type info here
    newCall("getResultPtr".ident())

func reduceAddr(s: ParamInfo): NimNode =
  if s.isStatic:
    newNilLit()
  elif s.isRefCountWrapper:
    newCall("addr".ident(), newDotExpr(newTree(nnkBracketExpr, s.binding), "opaque".ident()))
  else:
    newCall("getResultPtr".ident())

# Called in the second run-around of the macro expansion once type information
# is available to determine if we are dealing with an object type or a builtin
template getResultPtr*(): pointer {.dirty.} =
  when compiles(result.opaque):
    addr result.opaque
  elif compiles(result):
    addr result
  else:
    nil

template getParamPtr*(p: untyped): pointer {.dirty.} =
  when compiles(p.opaque):
    addr p.opaque
  else:
    addr p


func getVarArgs(prototype: NimNode): Option[NimNode] =
  if len(prototype[3]) > 1:
    let lastArg = prototype[3][^1]

    if lastArg[1].kind == nnkBracketExpr and lastArg[1][0].strVal == "varargs":
      return some lastArg

  none NimNode

func genArgsList(prototype: NimNode; argc: ptr int; ignoreFirst: bool = false): NimNode =
  result = newTree(nnkBracket)

  # If the first parameter is a typedesc[T] marker, skip it
  var skip = if len(prototype[3]) > 1 and prototype[3][1][0] == "_".ident():
    2
  else:
    # We ignore the first arg for (non-builtin) class methods because the instance
    # pointer is passed as separate argument.
    if ignoreFirst: 2 else: 1

  # Do not include the varargs here, they are handled specially
  let drop = if getVarArgs(prototype).isSome(): 1 else: 0

  if skip > len(prototype[3]) - 1:
    return

  for formalArgs in prototype[3][skip..^(1 + drop)]:
    for formalArg in formalArgs[0..^3]:
      inc argc[]

      result.add genAst(formalArg) do:
        pointer(unsafeAddr formalArg)

func getNameFromProto(proto: NimNode): string =
  if proto[0].kind in {nnkIdent, nnkSym}:
    # "funcname"
    proto[0].strVal()
  elif proto[0][1].kind in {nnkIdent, nnkSym}:
    # "funcname*"
    proto[0][1].strVal()
  else:
    # `quoted`
    proto[0][1][0].strVal()

# We need to put these into dedicated functions rather than `block:` statements due to
# bad codegen with destructors present.
proc getUtilityFunctionPtr(fun: static[string]; hash: static[int64]): GDExtensionPtrUtilityFunction =
  var gdFuncName = fun.toGodotStringName()

  gdInterfacePtr.variant_get_ptr_utility_function(addr gdFuncName, hash)

proc getBuiltinMethodPtr[T](meth: static[string]; hash: static[int64]): GDExtensionPtrBuiltInMethod =
  var gdFuncName = meth.toGodotStringName()

  gdInterfacePtr.variant_get_ptr_builtin_method(T.variantTypeId, addr gdFuncName, hash)

proc getClassMethodBindPtr*(cls, meth: static[string]; hash: static[int64]): GDExtensionMethodBindPtr =
  var gdClassName = cls.toGodotStringName()
  var gdMethName = meth.toGodotStringName()

  gdInterfacePtr.classdb_get_method_bind(addr gdClassName, addr gdMethName, hash)


macro gd_utility*(hash: static[int64]; prototype: untyped) =
  ## Implement a Godot utility function based upon the given proc declaration's name
  ## and a hash value derived from the API description.

  let functionName = prototype.getNameFromProto()

  var argc: int

  let resultPtr = prototype.resolveReturn().reducePtr()
  let varArgs = prototype.getVarArgs()
  let args = prototype.genArgsList(addr argc)

  result = prototype

  if varArgs.isNone():
    result[^1] = genAst(functionName, hash, args, argc, resultPtr) do:
      var p {.global.} = getUtilityFunctionPtr(functionName, hash)
      var argPtrs: array[argc, GDExtensionConstTypePtr] = args

      p(
        cast[GDExtensionTypePtr](resultPtr),
        cast[ptr GDExtensionConstTypePtr](addr argPtrs),
        cint(argc))
  else:
    let varArgId = varArgs.unsafeGet()[0]

    result[^1] = genAst(functionName, hash, args, argc, varArgId, resultPtr) do:
      var p {.global.} = getUtilityFunctionPtr(functionName, hash)
      var argPtrs = @args

      for i in 0..high(varArgId):
        argPtrs &= pointer(unsafeAddr varArgId[i])

      p(
        cast[GDExtensionTypePtr](resultPtr),
        cast[ptr GDExtensionConstTypePtr](addr argPtrs[0]),
        cint(argc + len(varArgId)))

# Builtins (Variant)

macro gd_builtin_ctor*(ty: typed; idx: static[int]; prototype: untyped) =
  ## Implement a Godot builtin constructor for the given type and
  ## constructor index.

  var argc: int
  let args = prototype.genArgsList(addr argc)

  result = prototype
  result[^1] = genAst(ty, idx, args, argc, result = ident"result") do:
    var p {.global.} = gdInterfacePtr.variant_get_ptr_constructor(
      ty.variantTypeId, int32(idx))

    var argPtrs: array[argc, GDExtensionConstTypePtr] = args

    p(addr result, cast[ptr GDExtensionConstTypePtr](addr argPtrs))

macro gd_builtin_dtor*(ty: typed; prototype: untyped) =
  ## Implement a Godot builtin destructor for the given type.

  let selfPtr = prototype.resolveSelf().reducePtr()

  result = prototype
  result[^1] = genAst(ty, selfPtr) do:
    var p {.global.} = gdInterfacePtr.variant_get_ptr_destructor(
      ty.variantTypeId)

    p(cast[GDExtensionTypePtr](selfPtr))


macro gd_builtin_method*(ty: typed; hash: static[int64]; prototype: untyped) =
  ## Implement a Godot builtin method for the given type, based upon the
  ## proc declaration's name and a hash value derived from the API description.

  let functionName = prototype.getNameFromProto()

  var argc: int

  let selfPtr = prototype.resolveSelf().reduceAddr()
  let resultPtr = prototype.resolveReturn().reducePtr()

  let args = prototype.genArgsList(addr argc)
  let varArgs = prototype.getVarArgs()

  result = prototype

  if varArgs.isNone():
    result[^1] = genAst(ty, functionName, hash, argc, args, selfPtr, resultPtr) do:
      var p {.global.} = getBuiltinMethodPtr[ty](functionName, hash)
      var argPtrs: array[argc, GDExtensionConstTypePtr] = args

      p(
        cast[GDExtensionTypePtr](selfPtr),
        cast[ptr GDExtensionConstTypePtr](addr argPtrs),
        cast[GDExtensionTypePtr](resultPtr),
        cint(argc))
  else:
    let varArgId = varArgs.unsafeGet()[0]

    result[^1] = genAst(ty, functionName, hash, argc, args, varArgId, selfPtr, resultPtr) do:
      var p {.global.} = block:
        var gdFuncName = functionName.toGodotStringName()

        gdInterfacePtr.variant_get_ptr_builtin_method(ty.variantTypeId, addr gdFuncName, hash)

      var argPtrs = @args

      for i in 0..high(varArgId):
        argPtrs &= pointer(unsafeAddr varArgId[i])

      p(
        cast[GDExtensionTypePtr](resultPtr),
        cast[ptr GDExtensionConstTypePtr](addr argPtrs[0]),
        cint(argc + len(varArgId)))

macro gd_builtin_set*(ty: typed; prototype: untyped) =
  let propertyName = prototype[0][1][0].strVal()

  let selfPtr = prototype.resolveSelf().reduceAddr()
  let valPtr = prototype[3][2][0]

  result = prototype
  result[^1] = genAst(propertyName, ty, selfPtr, valPtr):
    var p {.global.} = block:
      var gdFuncName = propertyName.toGodotStringName()

      gdInterfacePtr.variant_get_ptr_setter(ty.variantTypeId, addr gdFuncName)

    p(
      cast[GDExtensionTypePtr](selfPtr),
      cast[GDExtensionConstTypePtr](unsafeAddr valPtr))

func isKeyedIndex(node: NimNode): bool =
  node[3][2][^2].strVal == "Variant"

func indexParams(proto: NimNode; setter: bool; fn, idxType, idxNode: ptr NimNode) =
  let idx = proto[3][2][0]

  if proto.isKeyedIndex():
    fn[] = (if setter: "variant_get_ptr_keyed_setter" else: "variant_get_ptr_keyed_getter").ident()
    idxType[] = "GDExtensionConstTypePtr".bindSym()
    idxNode[] = newCall("unsafeAddr".ident(), idx)
  else:
    fn[] = (if setter: "variant_get_ptr_indexed_setter" else: "variant_get_ptr_indexed_getter").ident()
    idxType[] = "GDExtensionInt".bindSym()
    idxNode[] = idx

macro gd_builtin_index_get*(ty: typed; prototype: untyped) =
  var fn: NimNode
  var idxType: NimNode
  var idxNode: NimNode

  prototype.indexParams(false, addr fn, addr idxType, addr idxNode)

  let selfPtr = prototype.resolveSelf().reduceAddr()
  let resultPtr = prototype.resolveReturn().reducePtr()

  result = prototype
  result[^1] = genAst(fn, ty, selfPtr, idxType, idxNode, resultPtr) do:
    var p {.global.} = gdInterfacePtr.fn(ty.variantTypeId)

    p(
      cast[GDExtensionConstTypePtr](selfPtr),
      cast[idxType](idxNode),
      cast[GDExtensionTypePtr](resultPtr))

macro gd_builtin_index_set*(ty: typed; prototype: untyped) =
  var fn: NimNode
  var idxType: NimNode
  var idxNode: NimNode

  prototype.indexParams(true, addr fn, addr idxType, addr idxNode)

  let selfPtr = prototype.resolveSelf().reduceAddr()
  let valId = prototype[3][^1][^3]

  result = prototype
  result[^1] = genAst(fn, ty, selfPtr, idxType, idxNode, valId) do:
    var p {.global.} = gdInterfacePtr.fn(ty.variantTypeId)

    p(
      cast[GDExtensionConstTypePtr](selfPtr),
      cast[idxType](idxNode),
      cast[GDExtensionConstTypePtr](unsafeAddr valId))

func toOperatorId(oper: string; unary: bool): GDExtensionVariantOperator =
  case oper
    of "==": result = GDEXTENSION_VARIANT_OP_EQUAL
    of "!=": result = GDEXTENSION_VARIANT_OP_NOT_EQUAL
    of "<": result = GDEXTENSION_VARIANT_OP_LESS
    of "<=": result = GDEXTENSION_VARIANT_OP_LESS_EQUAL
    of ">": result = GDEXTENSION_VARIANT_OP_GREATER
    of ">=": result = GDEXTENSION_VARIANT_OP_GREATER_EQUAL
    of "+": result = if not unary: GDEXTENSION_VARIANT_OP_ADD else: GDEXTENSION_VARIANT_OP_POSITIVE
    of "-": result = if not unary: GDEXTENSION_VARIANT_OP_SUBTRACT else: GDEXTENSION_VARIANT_OP_NEGATE
    of "*": result = GDEXTENSION_VARIANT_OP_MULTIPLY
    of "/": result = GDEXTENSION_VARIANT_OP_DIVIDE
    of "%": result = GDEXTENSION_VARIANT_OP_MODULE
    of "**": result = GDEXTENSION_VARIANT_OP_POWER
    of "<<": result = GDEXTENSION_VARIANT_OP_SHIFT_LEFT
    of ">>": result = GDEXTENSION_VARIANT_OP_SHIFT_RIGHT
    of "&": result = GDEXTENSION_VARIANT_OP_BIT_AND
    of "|": result = GDEXTENSION_VARIANT_OP_BIT_OR
    of "^": result = GDEXTENSION_VARIANT_OP_BIT_XOR
    of "~": result = GDEXTENSION_VARIANT_OP_BIT_NEGATE
    of "and": result = GDEXTENSION_VARIANT_OP_AND
    of "or": result = GDEXTENSION_VARIANT_OP_OR
    of "xor": result = GDEXTENSION_VARIANT_OP_XOR
    of "not": result = GDEXTENSION_VARIANT_OP_NOT
    of "in": result = GDEXTENSION_VARIANT_OP_IN
    else:
      debugEcho "Unknown operator " & oper
      assert false

macro gd_builtin_operator*(ty: typed; prototype: untyped) =
  let isUnary = len(prototype[3]) < 3 and len(prototype[3][1]) < 4

  let lhsPtr = newCall("unsafeAddr".ident(), prototype[3][1][0])
  let lhsTyp = prototype[3][1][^2]

  var rhsPtr = newNilLit()
  var rhsTyp = "Variant".bindSym()

  if not isUnary:
    rhsPtr = newCall("unsafeAddr".ident(), prototype[3][^1][^3])
    rhsTyp = prototype[3][^1][^2]

  let rawOperatorName = prototype[0][1][0].strVal()
  let operatorId = rawOperatorName.toOperatorId(isUnary)

  result = prototype
  result[^1] = genAst(operatorId, lhsTyp, rhsTyp, lhsPtr, rhsPtr, result = ident"result") do:
    var p {.global.} = gdInterfacePtr.variant_get_ptr_operator_evaluator(
        cast[GDExtensionVariantOperator](operatorId),
        lhsTyp.variantTypeId,
        rhsTyp.variantTypeId)

    p(lhsPtr, rhsPtr, addr result)


# Classes

macro gd_class_ctor*(prototype: untyped) =
  let selfType = prototype.resolveReturn().reduceType()
  let selfTypeStr = selfType.strVal()

  result = prototype
  result[^1] = genAst(selfType, selfTypeStr, result = ident"result") do:
    var name = selfTypeStr.toGodotStringName()

    cast[selfType](gdInterfacePtr.object_get_instance_binding(
      gdInterfacePtr.classdb_construct_object(addr name),
      gdTokenPtr,
      selfType.gdInstanceBindingCallbacks))

macro gd_class_singleton*(prototype: untyped) =
  let selfType = prototype.resolveReturn().reduceType()

  result = prototype
  result[^1] = genAst(selfType) do:
    var name = selfType.gdClassName()

    cast[selfType](gdInterfacePtr.object_get_instance_binding(
      gdInterfacePtr.global_get_singleton(addr name),
      gdTokenPtr,
      selfType.gdInstanceBindingCallbacks))

macro gd_class_method*(hash: static[int64]; prototype: untyped) =
  var argc: int
  let args = prototype.genArgsList(addr argc, true)

  var s = prototype.resolveSelf()
  var r = prototype.resolveReturn()

  result = prototype
  result[^1] = genAst(
      selfType = s.reduceType(),
      selfPtr = s.reducePtr(),
      resultPtr = r.reducePtr(),
      methodName = prototype.getNameFromProto(),
      hash, argc, args):

    var p {.global.} = getClassMethodBindPtr($selfType, methodName, hash)
    var fixedArgs: array[argc, GDExtensionConstTypePtr] = args

    gdInterfacePtr.object_method_bind_ptrcall(
      p,
      cast[GDExtensionObjectPtr](selfPtr),
      cast[ptr GDExtensionConstTypePtr](addr fixedArgs),
      cast[GDExtensionTypePtr](resultPtr))

import ../nodot/ref_helper

template constructResultObject[T](dest: typedesc[Ref[T]]; raw: T): Ref[T] =
  newRefShallow(raw)

template constructResultObject[T](dest: typedesc[T]; raw: T): T =
  raw

macro gd_class_method_obj*(hash: static[int64]; prototype: untyped) =
  var argc: int
  let args = prototype.genArgsList(addr argc, true)

  var s = prototype.resolveSelf()
  var r = prototype.resolveReturn()

  result = prototype
  result[^1] = genAst(
      selfType = s.reduceType(),
      selfPtr = s.reducePtr(),
      methodName = prototype.getNameFromProto(),
      retType = r.reduceType(),
      fullRetType = r.fullType,
      hash, argc, args):

    var p {.global.} = getClassMethodBindPtr($selfType, methodName, hash)
    var fixedArgs: array[argc, GDExtensionConstTypePtr] = args

    var resultPtr: pointer = nil

    gdInterfacePtr.object_method_bind_ptrcall(
      p,
      cast[GDExtensionObjectPtr](selfPtr),
      cast[ptr GDExtensionConstTypePtr](addr fixedArgs),
      addr resultPtr)

    let instancePtr = cast[retType](gdInterfacePtr.object_get_instance_binding(
      resultPtr,
      gdTokenPtr,
      retType.gdInstanceBindingCallbacks))

    constructResultObject(fullRetType, instancePtr)

macro gd_builtin_get*(ty: typed; prototype: untyped) =
  let propertyName = prototype.getNameFromProto()

  let selfPtr = prototype.resolveSelf().reduceAddr()
  let resultPtr = prototype.resolveReturn().reducePtr()

  result = prototype
  result[^1] = genAst(propertyName, ty, selfPtr, resultPtr):
    var p {.global.} = block:
      var gdFuncName = propertyName.toGodotStringName()

      gdInterfacePtr.variant_get_ptr_getter(ty.variantTypeId, addr gdFuncName)

    p(
      cast[GDExtensionConstTypePtr](selfPtr),
      cast[GDExtensionTypePtr](resultPtr))

# Constants

proc gd_constant*[K, T](name: static[string]): T =
  var gdName = toGodotStringName(name)
  var resVariant: Variant

  gdInterfacePtr.variant_get_constant_value(
    cast[GDExtensionVariantType](T.variantTypeId),
    addr gdName,
    addr resVariant)

  resVariant.castTo(K)