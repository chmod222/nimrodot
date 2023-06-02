import ../nodot

import ./interface_ptrs
import ./builtins/types
import ./builtins/variant
import ./builtins/"string" as str
import ./classes/types/"object"
import ./enums

import std/[macros, genasts, tables, strutils, options, enumutils, typetraits, sugar, enumerate]

type
  ClassRegistration = object
    typeNode: NimNode
    parentNode: NimNode

    virtual: bool
    abstract: bool

    ctorFuncIdent: NimNode
    dtorFuncIdent: NimNode
    notificationHandlerIdent: NimNode
    revertQueryIdent: NimNode
    listPropertiesIdent: NimNode
    getPropertyIdent: NimNode
    setPropertyIdent: NimNode

    properties: OrderedTable[string, ClassProperty]
    methods: OrderedTable[string, MethodInfo]

    enums: seq[EnumInfo]
    consts: seq[ConstInfo]

  ClassProperty = object
    setter: NimNode
    getter: NimNode

  MethodInfo = object
    symbol: NimNode
    defaultValues: seq[DefaultedArgument]
    virtual: bool = false

  DefaultedArgument = object
    binding: NimNode
    default: NimNode

  EnumInfo = object
    definition: NimNode
    isBitfield: bool

  ConstInfo = object
    name: NimNode
    value: int

var classes* {.compileTime.} = initOrderedTable[string, ClassRegistration]()

macro custom_class*(def: untyped) =
  def[0].expectKind(nnkPragmaExpr)
  def[0][0].expectKind(nnkIdent)

  def[2].expectKind(nnkObjectTy)

  # Unless specified otherwise, we derive from Godot's "Object"
  if def[2][1].kind == nnkEmpty:
    def[2][1] = newTree(nnkOfInherit, "Object".ident())

  var
    abstract: bool = false
    virtual: bool = false

  for pragma in def[0][1]:
    if pragma.kind != nnkIdent:
      continue

    if pragma.strVal() == "gdvirtual":
      virtual = true
    elif pragma.strVal() == "abstract":
      abstract = true

  classes[def[0][0].strVal()] = ClassRegistration(
    typeNode: def[0][0],
    parentNode: def[2][1][0],

    virtual: virtual,
    abstract: abstract,

    ctorFuncIdent: newNilLit(),
    dtorFuncIdent: newNilLit(),
    notificationHandlerIdent: newNilLit(),
    revertQueryIdent: newNilLit(),
    listPropertiesIdent: newNilLit(),
    getPropertyIdent: newNilLit(),
    setPropertyIdent: newNilLit(),

    enums: @[])

  if def[2][1][0].strVal() notin classes:
    # If we are deriving from a Godot class as opposed to one of our own,
    # we add in a field to store our runtime class information into.
    def[2][2] &= newIdentDefs("gdclassinfo".ident(), "pointer".ident())

  def

# Unfortunately, "virtual" is already taken
template gdvirtual*() {.pragma.}
template abstract*() {.pragma.}

template expectClassReceiverProc(def: typed) =
  ## Helper function to assert that a proc definition with `x: var T` as the
  ## first parameter has been provided.
  def.expectKind(nnkProcDef)
  def[3][1][^2].expectKind(nnkVarTy)
  def[3][1][^2][0].expectKind(nnkSym)

template className(def: typed): string =
  if def[3][1][^2].kind == nnkVarTy:
    def[3][1][^2][0].strVal()
  else:
    def[3][1][^2][1].strVal()

macro ctor*(def: typed) =
  def.expectClassReceiverProc()

  classes[def.className].ctorFuncIdent = def[0]

  def

macro dtor*(def: typed) =
  def.expectClassReceiverProc()

  classes[def.className].dtorFuncIdent = def[0]

  def

macro classMethod*(def: typed) =
  def.expectClassReceiverProc()

  var defaults: seq[DefaultedArgument] = @[]

  if len(def[3]) > 1:
    for identDef in def[3][2..^1]:
      if identDef[^1].kind == nnkEmpty:
        continue

      for binding in identDef[0..^3]:
        defaults &= DefaultedArgument(
          binding: binding,
          default: identDef[^1])

  var virtual = false

  # macros.hasCustomPragma somehow always return false here
  for pragma in def[4]:
    if pragma.strVal() == "gdvirtual":
      virtual = true

  classes[def.className].methods[def[0].strVal()] = MethodInfo(
    symbol: def[0],
    defaultValues: defaults,
    virtual: virtual,
  )

  def

macro staticMethod*(T: typedesc; def: typed) =
  def.expectKind(nnkProcDef)

  var defaults: seq[DefaultedArgument] = @[]

  if len(def[3]) > 1:
    for identDef in def[3][2..^1]:
      if identDef[^1].kind == nnkEmpty:
        continue

      for binding in identDef[0..^3]:
        defaults &= DefaultedArgument(
          binding: binding,
          default: identDef[^1])

  classes[$T].methods[def[0].strVal()] = MethodInfo(
    symbol: def[0],
    defaultValues: defaults,
    virtual: false,
  )

  def

macro notification*(def: typed) =
  def.expectClassReceiverProc()

  classes[def.className].notificationHandlerIdent = def[0]

  def

macro property*(def: typed) =
  def.expectKind(nnkProcDef)

  def[0].expectKind(nnkSym)

  let isSetter = def[0].strVal().endsWith('=')

  if isSetter:
    # Property setter function
    def[3][0].expectKind(nnkEmpty)
    def[3][1][1].expectKind(nnkVarTy)

    def[3][2][1].expectIdent("Variant") # for now

  else:
    # Property getter function
    def[3][0].expectKind(nnkSym)
    def[3][0].expectIdent("Variant") # for now
    def[3][1][1].expectKind(nnkVarTy)

  let classType = def[3][1][1][0]
  let propertyName = if isSetter: def[0].strVal()[0..^2] else: def[0].strVal()

  var p = classes[classType.strVal()].properties.mgetOrPut(propertyName, default(ClassProperty))

  if isSetter:
    p.setter = def[0]
  else:
    p.getter = def[0]

  def

macro revertQuery*(def: typed) =
  def.expectKind(nnkProcDef)

  def[0].expectKind(nnkSym)
  def[3].expectLen(3)

  def[3][0][0].expectIdent("Option")
  def[3][0][1].expectIdent("Variant")

  def[3][1][1].expectKind(nnkVarTy)

  def[3][2][1].expectIdent("StringName")

  let classType = def[3][1][1][0]

  classes[classType.strVal()].revertQueryIdent = def[0]

  def

macro propertyQuery*(def: typed) =
  def.expectClassReceiverProc()

  def[3].expectLen(3)

  # No return
  def[3][0].expectKind(nnkEmpty)

  # var seq[GDExtensionPropretyInfo]
  def[3][2][^2].expectKind(nnkVarTy)
  def[3][2][^2][0].expectKind(nnkBracketExpr)
  def[3][2][^2][0][0].expectIdent("seq")
  def[3][2][^2][0][1].expectIdent("GDExtensionPropertyInfo")

  let classType = def[3][1][1][0]

  classes[classType.strVal()].listPropertiesIdent = def[0]

  def

macro getProperty*(def: typed) =
  def.expectClassReceiverProc()
  let classType = def[3][1][1][0]

  classes[classType.strVal()].getPropertyIdent = def[0]

  def

macro setProperty*(def: typed) =
  def.expectClassReceiverProc()
  let classType = def[3][1][1][0]

  classes[classType.strVal()].setPropertyIdent = def[0]

  def

proc classEnumImpl(T: NimNode; isBitfield: bool; def: NimNode): NimNode =
  def.expectKind(nnkTypeDef)
  def[2].expectKind(nnkEnumTy)

  classes[$T].enums &= EnumInfo(
    definition: def,
    isBitfield: isBitfield)

  def

macro classEnum*(T: typedesc; def: untyped) =
  result = classEnumImpl(T, false, def)

macro classBitfield*(T: typedesc; def: untyped) =
  result = classEnumImpl(T, true, def)

macro constant*(T: typedesc; def: typed) =
  def.expectKind(nnkConstSection)

  for constDef in def:
    constDef[2].expectKind(nnkIntLit)

    classes[$T].consts &= ConstInfo(
      name: constDef[0],
      value: constDef[2].intVal())

  def

include internal/typeinfo

proc create_callback(token, instance: pointer): pointer {.cdecl.} = nil
proc free_callback(token, instance, binding: pointer) {.cdecl.} = discard
proc reference_callback(token, instance: pointer; reference: GDExtensionBool): GDExtensionBool {.cdecl.} = 1

var nopOpBinding = GDExtensionInstanceBindingCallbacks(
  create_callback: create_callback,
  free_callback: free_callback,
  reference_callback: reference_callback)

type
  ConstructorFunc[T] = proc(obj: var T)
  DestructorFunc[T] = proc(obj: var T)

  NotificationHandlerFunc[T] = proc(obj: var T; what: int)
  RevertQueryFunc[T] = proc(obj: var T; propertyName: StringName): Option[Variant]
  PropertyListFunc[T] = proc(obj: var T; properties: var seq[GDExtensionPropertyInfo])

  PropertyGetterFunc[T] = proc(obj: var T; propertyName: StringName): Option[Variant]
  PropertySetterFunc[T] = proc(obj: var T; propertyName: StringName; value: Variant): bool

  RuntimeClassRegistration[T] = object
    lastGodotAncestor: StringName = "Object"

    ctor: ConstructorFunc[T]
    dtor: DestructorFunc[T]

    notifierFunc: NotificationHandlerFunc[T]
    revertFunc: RevertQueryFunc[T]
    propertyListFunc: PropertyListFunc[T]

    getFunc: PropertyGetterFunc[T]
    setFunc: PropertySetterFunc[T]

proc create_instance[T, P](userdata: pointer): pointer {.cdecl.} =
  var nimInst = cast[ptr T](gdInterfacePtr.mem_alloc(sizeof(T).csize_t))
  var rcr = cast[ptr RuntimeClassRegistration[T]](userdata)

  var className = ($T).StringName
  var lastNativeClassName = rcr.lastGodotAncestor

  # We construct the parent class and store it into our opaque pointer field, so we have
  # a handle from Godot, for Godot.
  nimInst.opaque = gdInterfacePtr.classdb_construct_object(addr lastNativeClassName)
  nimInst.gdclassinfo = userdata

  rcr.ctor(nimInst[])

  # We tell Godot what the actual type for our object is and bind our native class to
  # its native class.
  gdInterfacePtr.object_set_instance(nimInst.opaque, addr className, nimInst)
  gdInterfacePtr.object_set_instance_binding(nimInst.opaque, gdTokenPtr, nimInst, addr nopOpBinding)

  nimInst.opaque

proc free_instance[T, P](userdata: pointer; instance: GDExtensionClassInstancePtr) {.cdecl.} =
  var nimInst = cast[ptr T](instance)
  var rcr = cast[ptr RuntimeClassRegistration[T]](userdata)

  rcr.dtor(nimInst[])

  gdInterfacePtr.mem_free(nimInst)

proc instance_to_string[T](instance: GDExtensionClassInstancePtr;
                           valid: ptr GDExtensionBool;
                           str: GDExtensionStringPtr) {.cdecl.} =
  var nimInst = cast[ptr T](instance)

  when compiles($nimInst[]):
    gdInterfacePtr.string_new_with_utf8_chars(str, cstring($nimInst[]))
    valid[] = 1
  else:
    valid[] = 0

proc instance_notification[T](instance: GDExtensionClassInstancePtr;
                              what: int32) {.cdecl.} =
  var nimInst = cast[ptr T](instance)
  let regInst = cast[ptr RuntimeClassRegistration[T]](nimInst.gdclassinfo)

  if regInst.notifierFunc.isNil():
    return

  regInst.notifierFunc(nimInst[], int(what))

proc instance_virt_query[T](instance: GDExtensionClassInstancePtr;
                            methodName: GDExtensionConstStringNamePtr): GDExtensionClassCallVirtual
                            {.cdecl.} =
  var nimInst = cast[ptr T](instance)
  var methodName = cast[ptr StringName](methodName)

  nil

proc can_property_revert[T](instance: GDExtensionClassInstancePtr;
                            name: GDExtensionConstStringNamePtr): GDExtensionBool {.cdecl.} =
  var nimInst = cast[ptr T](instance)
  var prop = cast[ptr StringName](name)
  let regInst = cast[ptr RuntimeClassRegistration[T]](nimInst.gdclassinfo)

  if regInst.revertFunc.isNil():
    return 0

  GDExtensionBool(regInst.revertFunc(nimInst[], prop[]).isSome())

proc property_revert[T](instance: GDExtensionClassInstancePtr;
                        name: GDExtensionConstStringNamePtr;
                        ret: GDExtensionVariantPtr): GDExtensionBool {.cdecl.} =
  var nimInst = cast[ptr T](instance)
  var prop = cast[ptr StringName](name)
  var retPtr = cast[ptr Variant](ret)
  let regInst = cast[ptr RuntimeClassRegistration[T]](nimInst.gdclassinfo)

  if regInst.revertFunc.isNil():
    return 0

  let revertValue = regInst.revertFunc(nimInst[], prop[])

  if revertValue.isNone():
    return 0

  retPtr[] = revertValue.unsafeGet()

  return 1

# Since we deal with a lot of compile time know stuff, this comes in
# useful quite often. As the function is generated once per string,
# we have our own interning of interned strings.
proc staticStringName(s: static[string]): ptr StringName =
  var interned {.global.}: StringName = s

  addr interned

proc gdClassName[T: AnyObject](_: typedesc[T]): ptr StringName =
  staticStringName($T)

type
  PropertyInfo*[T] = object
    name: StringName
    hint: StringName = ""
    propertyType: typedesc[T]
    propertyUsage: uint32 = uint32(pufDefault)
    propertyHint: uint32 = uint32(phiNone)

proc addPropertyInfo*[T](list: var seq[GDExtensionPropertyInfo]; info: PropertyInfo[T]) =
  when T is AnyObject:
    var classNamePtr = gdClassName(T)
  else:
    var classNamePtr = staticStringName("")

  var namePtr = create(StringName)
  var hintPtr = create(StringName)

  namePtr[] = info.name
  hintPtr[] = info.hint

  list &= GDExtensionPropertyInfo(
    name: namePtr,
    `type`: T.variantTypeId(),
    class_name: classNamePtr,
    hint: info.propertyHint,
    hint_string: hintPtr,
    usage: info.propertyUsage)

proc addPropertyInfo*[T](list: var seq[GDExtensionPropertyInfo]; name: StringName; hint: StringName = "") =
  list.addPropertyInfo(PropertyInfo[T](name: name, hint: hint))

type
  # GDExtension does not tell us (in free_class_properties), how many properties
  # we gave it in list_class_properties, but we have to iterate over it to free
  # the names we allocated previously. So we use the old C trick of allocating the
  # list with a little prefix to store our count in, followed by the actual list payload,
  # give Godot the offset pointer to `elems` and calculate the reverse when it's time to
  # free the list.
  #
  # This is slightly more expensive than letting the library user cache a list of their
  # properties and returning it in order to guarantee the fields are kept alive until
  # the free callback (like godot-cpp does), but it's also much more convenient and unless
  # get_property_list() is invoked in a hot loop it shouldn't make a difference.
  LenPrefixedPropertyInfo = object
    count: uint32
    elems: UncheckedArray[GDExtensionPropertyInfo]

proc list_class_properties[T](instance: GDExtensionClassInstancePtr;
                              count: ptr uint32): ptr GDExtensionPropertyInfo {.cdecl.} =
  var nimInst = cast[ptr T](instance)
  let regInst = cast[ptr RuntimeClassRegistration[T]](nimInst.gdclassinfo)

  var properties = newSeq[GDExtensionPropertyInfo]()

  if not regInst.propertyListFunc.isNil():
    regInst.propertyListFunc(nimInst[], properties)

  count[] = uint32 len(properties)

  if regInst.propertyListFunc.isNil() or len(properties) == 0:
    return nil

  let size = sizeOf(LenPrefixedPropertyInfo) + (sizeOf(GDExtensionPropertyInfo) * len(properties))
  let prefixed = cast[ptr LenPrefixedPropertyInfo](alloc(size))

  prefixed[].count = count[]

  var propertyInfos = cast[ptr UncheckedArray[GDExtensionPropertyInfo]](addr prefixed[].elems)

  for i, property in enumerate(properties):
    propertyInfos[i] = property

  result = cast[ptr GDExtensionPropertyInfo](addr prefixed[].elems)

proc free_class_properties[T](instance: GDExtensionClassInstancePtr;
                              list: ptr GDExtensionPropertyInfo) {.cdecl.} =
  let offset = offsetOf(LenPrefixedPropertyInfo, elems)
  let prefixed = cast[ptr LenPrefixedPropertyInfo](cast[pointer](cast[int](list) - offset))

  if not list.isNil():
    for i in 0..prefixed[].count - 1:
      `=destroy`(prefixed[].elems[i].name)
      `=destroy`(prefixed[].elems[i].hint_string)

      dealloc(prefixed[].elems[i].name)
      dealloc(prefixed[].elems[i].hint_string)

    dealloc(list)

proc property_set[T](instance: GDExtensionClassInstancePtr;
                     name: GDExtensionConstStringNamePtr;
                     value: GDExtensionConstVariantPtr): GDExtensionBool {.cdecl.} =
  var nimInst = cast[ptr T](instance)
  let regInst = cast[ptr RuntimeClassRegistration[T]](nimInst.gdclassinfo)
  var prop = cast[ptr StringName](name)
  var value = cast[ptr Variant](value)

  result = 0

  if not regInst.setFunc.isNil():
    result = GDExtensionBool(regInst.setFunc(nimInst[], prop[], value[]))

proc property_get[T](instance: GDExtensionClassInstancePtr;
                     name: GDExtensionConstStringNamePtr;
                     value: GDExtensionVariantPtr): GDExtensionBool {.cdecl.} =
  var nimInst = cast[ptr T](instance)
  let regInst = cast[ptr RuntimeClassRegistration[T]](nimInst.gdclassinfo)

  var prop = cast[ptr StringName](name)
  var retValue = cast[ptr Variant](value)

  var value = none Variant

  result = 0

  if not regInst.getFunc.isNil():
    value = regInst.getFunc(nimInst[], prop[])
    result = GDExtensionBool(value.isSome())

    if value.isSome():
      retValue[] = value.unsafeGet()


proc registerClass*[T, P](
    lastNative: StringName,
    ctorFunc: ConstructorFunc[T];
    dtorFunc: DestructorFunc[T];
    notification: NotificationHandlerFunc[T];
    revertQuery: RevertQueryFunc[T];
    listProperties: PropertyListFunc[T];
    getProperty: PropertyGetterFunc[T];
    setProperty: PropertySetterFunc[T];
    abstract, virtual: bool = false) =

  var className: StringName = $T
  var parentClassName: StringName = $P

  when T isnot AnyObject:
    {.warning: "T really should derive (directly or indrectly) from `Object`.".}

  # Needs static lifetime, so {.global.}
  var rcr {.global.}: RuntimeClassRegistration[T] = RuntimeClassRegistration[T](
    ctor: ctorFunc,
    dtor: dtorFunc,
    notifierFunc: notification,
    lastGodotAncestor: lastNative,
    revertFunc: revertQuery,
    propertyListFunc: listProperties,
    getFunc: getProperty,
    setfunc: setProperty
  )

  var creationInfo = GDExtensionClassCreationInfo(
    is_virtual: GDExtensionBool(virtual),
    is_abstract: GDExtensionBool(abstract),

    set_func: property_set[T],
    get_func: property_get[T],

    get_property_list_func: list_class_properties[T],
    free_property_list_func: free_class_properties[T],

    property_can_revert_func: can_property_revert[T],
    property_get_revert_func: property_revert[T],

    notification_func: instance_notification[T],
    to_string_func: instance_to_string[T],
    reference_func: nil,
    unreference_func: nil,

    create_instance_func: create_instance[T, P], # default ctor
    free_instance_func: free_instance[T, P],     # dtor
    get_virtual_func: instance_virt_query[T],
    get_rid_func: nil,

    class_userdata: addr rcr)

  gdInterfacePtr.classdb_register_extension_class(
    gdTokenPtr,
    addr className,
    addr parentClassName,
    addr creationInfo)

type
  ReturnValueInfo = tuple
    returnValue: GDExtensionPropertyInfo
    returnMeta: GDExtensionClassMethodArgumentMetadata

proc gdClassName(_: typedesc): ptr StringName = staticStringName("")


macro getReturnInfo(M: typed): Option[ReturnValueInfo] =
  let typeInfo = M.getType()[1]

  if typeInfo[1].strVal() == "void":
    return genAst: none ReturnValueInfo

  return genAst(R = typeInfo[1]):
    some (
      returnValue: GDExtensionPropertyInfo(
        `type`: variantTypeId(typeOf R),
        name: staticStringName(""),
        class_name: gdClassName(typeOf R),
        hint: uint32(propertyHint(typeOf R)),
        hint_string: staticStringName(""),
        usage: uint32(propertyUsage(typeOf R))
      ),
      returnMeta: typeMetaData(typeOf R))

macro getMethodFlags(M: typed): static[set[GDExtensionClassMethodFlags]] =
  let typedM = M.getType()[1].getTypeImpl()

  var setLiteral = newTree(nnkCurly,
    "GDEXTENSION_METHOD_FLAGS_DEFAULT".ident())

  if len(typedM[0]) > 1:
    let firstParam = typedM[0][1]
    let lastParam = typedM[0][^1]

    if firstParam[1].kind != nnkVarTy:
      setLiteral &= "GDEXTENSION_METHOD_FLAG_STATIC".ident()

    if lastParam[1].kind == nnkBracketExpr and
        lastParam[1][0].strVal() == "varargs":
      setLiteral &= "GDEXTENSION_METHOD_FLAG_VARARG".ident()

  genAst(setLiteral):
    setLiteral

func isVarArg(m: NimNode): bool =
  result = m.kind == nnkBracketExpr and m[0].strVal() == "varargs"

macro getProcProps(M: typed): auto =
  let typedM = M.getType()[1].getTypeImpl()

  var argc = 0

  var args = newTree(nnkBracket)
  var argsMeta = newTree(nnkBracket)

  if len(typedM[0]) > 2:
    for defs in typedM[0][2..^1]:
      if defs[^2].isVarArg():
        break

      for binding in defs[0..^3]:
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

  result = genAst(procArgc = argc, procArgs = args, procArgsMeta = argsMeta):
    tuple[pargc: int,
          pargs: array[procArgc, GDExtensionPropertyInfo],
          pmeta: array[procArgc, GDExtensionClassMethodArgumentMetadata]](
      pargc: procArgc,
      pargs: procArgs,
      pmeta: procArgsMeta)

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

# Call a function with a number of Variant pointers (bindcall)
macro callBindFunc(
    def: typed;
    self: typed;
    argsArray: ptr UncheckedArray[ptr Variant];
    argc: typed;
    argPos: int32): auto =
  let typedFunc = def.getTypeInst()[0]

  var argsStart = 1

  result = newTree(nnkCall, def)

  if len(typedFunc) > 1:
    if typedFunc[1][^2].kind == nnkVarTy:
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
macro callPtrFunc(
    def: typed;
    self: typed;
    argsArray: ptr UncheckedArray[GDExtensionConstTypePtr]): auto =
  let typedFunc = def.getTypeInst()[0]

  var argsStart = 1

  result = newTree(nnkCall, def)

  if len(typedFunc) > 1:
    if typedFunc[1][^2].kind == nnkVarTy:
      result &= newTree(nnkBracketExpr, self)

      inc argsStart

    for i, arg in enumerate(typedFunc[argsStart..^1]):
      let argBody = if arg[^2].isVarArg():
        # Cannot be done using ptrcall, so we leave it empty in case
        # a vararg function is ever called using ptrcall.
        break
      else:
        genAst(T = arg[^2], argsArray, i):
          maybeDowncast[T](argFromPointer[mapBuiltinType(typeOf T)](argsArray[i]))

      result &= argBody

proc invoke_method*[T, M](userdata: pointer;
                          instance: GDExtensionClassInstancePtr;
                          args: ptr GDExtensionConstVariantPtr;
                          argc: GDExtensionInt;
                          ret: GDExtensionVariantPtr;
                          error: ptr GDExtensionCallError) {.cdecl.} =

  let nimInst = cast[ptr T](instance)
  let callable = cast[M](userdata)

  let argArray = cast[ptr UncheckedArray[ptr Variant]](args)
  var argPos = 0'i32
  let returnValue = cast[ptr Variant](ret)

  type
    R = callable.procReturn()

  const arity = callable.procArity()

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
    when R is void:
      callable.callBindFunc(nimInst, argArray, argc, argPos)
    else:
      returnValue[] = %maybeDowncast[mapBuiltinType R](callable.callBindFunc(nimInst, argArray, argc, argPos))

  except CallMarshallingError as cme:
    error[].error = GDEXTENSION_CALL_ERROR_INVALID_ARGUMENT
    error[].argument = cme.argument
    error[].expected = cme.expected

  except CatchableError:
    # For the lack of a better option
    error[].error = GDEXTENSION_CALL_ERROR_INVALID_METHOD

proc invoke_method_ptrcall*[T, M](
    userdata: pointer;
    instance: GDExtensionClassInstancePtr;
    args: ptr GDExtensionConstTypePtr;
    returnPtr: GDExtensionTypePtr) {.cdecl.} =

  let nimInst = cast[ptr T](instance)
  let callable = cast[M](userdata)
  let argArray = cast[ptr UncheckedArray[GDExtensionConstTypePtr]](args)

  type R = callable.procReturn()

  when R is void:
    callable.callPtrFunc(nimInst, argArray)
  else:
    cast[ptr mapBuiltinType(typeOf R)](returnPtr)[] = callable.callPtrFunc(nimInst, argArray)

# Murmur3-32 is used to calculate the method hashes, we may need to replicate those.
func murmur3(input: uint32; seed: uint32 = 0x7F07C65): uint32 =
  var input = input
  var seed = seed

  input *= 0xCC9E2D51'u32
  input = (input shl 15) or (input shr 17)
  input *= 0x1B873593'u32

  seed = seed xor input
  seed = (seed shl 13) or (seed shr 19)
  seed = seed * 5 + 0xE6546b64'u32

  seed

func fmix32(input: uint32): uint32 =
  result = input

  result = result xor (result shr 16)
  result *= 0x85EBCA6B'u32
  result = result xor (result shr 13)
  result *= 0xC2B2AE35'u32
  result = result xor (result shr 16)

proc calculateHash(
    returnValue: Option[GDExtensionPropertyInfo];
    args: openArray[GDExtensionPropertyInfo];
    defaults: openArray[Variant];
    flags: uint32): uint32 =
  result = murmur3(uint32(returnValue.isSome()))
  result = murmur3(uint32(args.len()), result)

  if returnValue.isSome():
    let clsName = cast[ptr StringName](returnValue.unsafeGet().class_name)

    result = murmur3(uint32(returnValue.unsafeGet().`type`), result)

    if (clsName != staticStringName("")):
      result = murmur3(uint32(clsName[].String.hash()), result)

  for arg in args:
    let clsName = cast[ptr StringName](arg.class_name)

    result = murmur3(uint32(arg.`type`), result)

    if (clsName != staticStringName("")):
      result = murmur3(uint32(clsName[].String.hash()), result)

  result = murmur3(uint32(len(defaults)), result)

  for default in defaults:
    result = murmur3(uint32(default.hash()), result)

  result = murmur3(uint32((GDEXTENSION_METHOD_FLAG_CONST.ord and flags) > 0), result)
  result = murmur3(uint32((GDEXTENSION_METHOD_FLAG_VARARG.ord and flags) > 0), result)
  result = fmix32(result)

proc registerMethod*[T](
    name: string;
    callable: auto;
    defaults: auto;
    virtual: bool = false) =
  var className: StringName = $T
  var methodName: StringName = name

  type M = typeOf callable

  # TODO: The {.classMethod.} macros ensures every proc here has a typedesc[T] or var T
  #       parameter at the first position. This function does not, but it can still be
  #       called manually if need be, so we must verify here as well.

  var returnInfo = M.getReturnInfo()
  var rvInfo: ptr GDExtensionPropertyInfo = nil
  var rvMeta = GDEXTENSION_METHOD_ARGUMENT_METADATA_NONE
  var defaultFlags = uint32 GDEXTENSION_METHOD_FLAGS_DEFAULT

  if virtual:
    defaultFlags = defaultFlags or (uint32 GDEXTENSION_METHOD_FLAG_VIRTUAL)

  {.hint[ConvFromXtoItselfNotNeeded]: off.}
  {.warning[HoleEnumConv]: off.}

  for flag in M.getMethodFlags():
    defaultFlags = defaultFlags or (uint32 flag)

  {.warning[HoleEnumConv]: on.}

  if returnInfo.isSome():
    rvInfo = addr returnInfo.unsafeGet().returnValue
    rvMeta = returnInfo.unsafeGet().returnMeta

  let argProperties = M.getProcProps()

  {.hint[ConvFromXtoItselfNotNeeded]: on.}

  var defaultVariants = newSeq[Variant]()

  # fieldPairs() doesn't play well with collect(), so we can't be fancy here
  for param, default in defaults.fieldPairs():
    defaultVariants &= %default

  var defaultVariantPtrs = collect(newSeqOfCap(len(defaultVariants))):
    for i in 0..high(defaultVariants):
      cast[ptr GDExtensionVariantPtr](addr defaultVariants[i])

  # Highly useful for debugging despite not 100% match Godot's yet
  #
  #var hash = calculateHash(
  #  returnInfo.map(proc(s: ReturnValueInfo): GDExtensionPropertyInfo = s.returnValue),
  #  argProperties.pargs,
  #  defaultVariants,
  #  defaultFlags)

  var methodInfo = GDExtensionClassMethodInfo(
    name: addr methodName,
    method_userdata: callable,

    call_func: invoke_method[T, M],
    ptrcall_func: invoke_method_ptrcall[T, M],
    method_flags: defaultFlags,

    has_return_value: GDExtensionBool(returnInfo.isSome()),
    return_value_info: rvInfo,
    return_value_metadata: rvMeta,

    argument_count: uint32(argProperties.pargc),
    arguments_info: cast[ptr GDExtensionPropertyInfo](addr argProperties.pargs),
    arguments_metadata: cast[ptr GDExtensionClassMethodArgumentMetadata](addr argProperties.pmeta),

    default_argument_count: uint32(len(defaultVariantPtrs)),
    default_arguments: if len(defaultVariantPtrs) > 0:
      cast[ptr GDExtensionVariantPtr](addr defaultVariantPtrs[0])
    else:
      nil,
  )

  gdInterfacePtr.classdb_register_extension_class_method(
    gdTokenPtr,
    addr className,
    addr methodInfo)

iterator possiblyHoleyItems[E: enum](_: typedesc[E]): E =
  when E is HoleyEnum:
    for elem in enumutils.items(E): yield elem
  else:
    for elem in E: yield elem

proc registerClassEnum*[T, E: enum](t: typedesc[E]; isBitfield: bool = false) =
  var className: StringName = $T
  var enumName: StringName = $E

  {.warning[HoleEnumConv]: off.}

  for value in possiblyHoleyItems(E):
    var fieldName: StringName = $value

    gdInterfacePtr.classdb_register_extension_class_integer_constant(
      gdTokenPtr,
      addr className,
      addr enumName,
      addr fieldName,
      GDExtensionInt(ord(value)),
      GDExtensionBool(isBitfield))

  {.warning[HoleEnumConv]: on.}

proc registerClassConstant*[T](name: string; value: int) =
  var className: StringName = $T
  var constName: StringName = name

  gdInterfacePtr.classdb_register_extension_class_integer_constant(
    gdTokenPtr,
    addr className,
    staticStringName(""),
    addr constName,
    GDExtensionInt(value),
    GDExtensionBool(false))


proc generateDefaultsTuple(mi: MethodInfo): NimNode =
  result = newTree(nnkTupleConstr)

  for default in mi.defaultValues:
    result &= newTree(nnkExprColonExpr,
      default.binding,
      default.default)

macro register*() =
  result = newStmtList()

  for className, regInfo in classes:
    # Because we (apparently) cannot cleanly derive from our own classes, we establish
    # the latest class that is native to Godot and "derive" from that. The instance is
    # still registered to the correct parent class type, but everything after the
    # last Godot class is handled Nim-side.
    var lastAncestor = regInfo.parentNode.strVal()

    while lastAncestor in classes:
      lastAncestor = classes[lastAncestor].parentNode.strVal()

    let classReg = genAst(
        lastAncestor,
        T = regInfo.typeNode,
        P = regInfo.parentNode,
        ctor = regInfo.ctorFuncIdent,
        dtor = regInfo.dtorFuncIdent,
        notification = regInfo.notificationHandlerIdent,
        revertQuery = regInfo.revertQueryIdent,
        listProperties = regInfo.listPropertiesIdent,
        getProp = regInfo.getPropertyIdent,
        setProp = regInfo.setPropertyIdent,
        isAbstract = regInfo.abstract,
        isVirtual = regInfo.virtual):

      registerClass[T, P](
        lastAncestor,
        ctor,
        dtor,
        notification,
        revertQuery,
        listProperties,
        getProp,
        setProp,
        isAbstract,
        isVirtual)

    result.add(classReg)

    for methodName, methodInfo in regInfo.methods:
      let methodReg = genAst(
          T = regInfo.typeNode,
          methodName,
          methodSymbol = methodInfo.symbol,
          defaultArgs = methodInfo.generateDefaultsTuple,
          isVirtual = methodInfo.virtual):

        registerMethod[T](methodName, methodSymbol, defaultArgs, isVirtual)

      result.add(methodReg)

    for enumDef in regInfo.enums:
      let enumReg = genAst(
          T = regInfo.typeNode,
          E = enumDef.definition[0][0],
          isBitfield = enumDef.isBitfield):

        registerClassEnum[T, E](E, isBitfield)

      result.add(enumReg)

    for constDef in regInfo.consts:
      let constReg = genAst(
          T = regInfo.typeNode,
          name = constDef.name.strVal(),
          value = constDef.value):

        registerClassConstant[T](name, value)

      result.add(constReg)