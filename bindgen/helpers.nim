import std/[options, enumerate, strutils, strformat, sets, tables, sugar]

import ./api

var apiDef*: Api

import ./gdtype
export gdtype

func typeId(name: string): int =
  case name
    of "Nil": 0
    of "bool": 1
    of "int": 2
    of "float": 3
    of "String": 4
    of "Vector2": 5
    of "Vector2i": 6
    of "Rect2": 7
    of "Rect2i": 8
    of "Vector3": 9
    of "Vector3i": 10
    of "Transform2D": 11
    of "Vector4": 12
    of "Vector4i": 13
    of "Plane": 14
    of "Quaternion": 15
    of "AABB": 16
    of "Basis": 17
    of "Transform3D": 18
    of "Projection": 19
    of "Color": 20
    of "StringName": 21
    of "NodePath": 22
    of "RID": 23
    of "Object": 24
    of "Callable": 25
    of "Signal": 26
    of "Dictionary": 27
    of "Array": 28
    of "PackedByteArray": 29
    of "PackedInt32Array": 30
    of "PackedInt64Array": 31
    of "PackedFloat32Array": 32
    of "PackedFloat64Array": 33
    of "PackedStringArray": 34
    of "PackedVector2Array": 35
    of "PackedVector3Array": 36
    of "PackedColorArray": 37
    else: -1

func typeId*(def: BuiltinClassDefinition): int =
  let id = def.name.typeId

  if id >= 0:
    return id
  else:
    raise newException(ValueError, "bad builtin class " & def.name)

func isBuiltinClass*(name: string): bool = name.typeId >= 0

const reservedWords = block:
  var words = initHashSet[string]()
  const reserved = """
    string int float bool array result
    addr and as asm
    bind block break
    case cast concept const continue converter
    defer discard distinct div do
    elif else end enum except export
    finally for from func
    if import in include interface is isnot iterator
    let
    macro method mixin mod
    nil not notin
    object of or out
    proc ptr
    raise ref return
    shl shr static
    template try tuple type
    using
    var
    when while
    xor
    yield"""

  for word in reserved.split():
    incl words, word

  words

func isReservedWord*(ident: string): bool =
  if ident in reservedWords:
    return true

  case ident
    of "nil", "from", "type", "object", "method", "func", "end", "mixin", "bind", "mod", "div": return true
    else: return false

type
  DependencyHint* = enum
    dhGlobalEnums
    dhCoreClasses

  TypedEnum* = tuple
    class: Option[string]
    enumName: string

func parseTypedEnum*(e: string): TypedEnum =
  let offset = if e.startsWith("enum::"): 6 else: 10
  let normalized = e[offset..^1]

  if '.' in normalized:
    let r = normalized.split('.')

    result.class = some r[0]
    result.enumName = r[1]
  else:
    result.class = none string
    result.enumName = normalized

func moduleName*(className: string): string =
  className.toLower()

func moduleName*(class: BuiltinClassDefinition): string =
  class.name.moduleName()

func moduleName*(class: ClassDefinition): string =
  class.name.moduleName()

func render*(t: GodotType): string =
  let actualType = t.metaType.get(t.rawType)
  let isMember = t.kind == tkField

  result = case actualType:
    of "int":
      if isMember: "int32" else: "int64"

    of "float":
      if isMember: "float32" else: "float64"

    of "double":
      if isMember: "float64" else: "float64"

    of "const void*", "void*": "pointer"

    of "real_t": "float64"

    of "uint8_t": "uint8"
    of "uint16_t": "uint16"
    of "uint32_t": "uint32"
    of "uint64_t": "uint64"

    of "int8_t": "int8"
    of "int16_t": "int16"
    of "int32_t", "int32": "int32"
    of "int64_t": "int64"
    else:
      actualType

  if result.startsWith("typedarray::"):
    result = "TypedArray[" & result[12..^1] & "]"

  if result.startsWith("enum::") or result.startsWith("bitfield::"):
    # enums and bitfields are the same for our purposes
    let te = actualType.parseTypedEnum()

    if te.class.isSome():
      result = te.class.unsafeGet().moduleName() & "." & te.enumName
    else:
      result = te.enumName

  if tfRefType in t.flags:
    result = "Ref[" & result & "]"

  if tfVarType in t.flags:
    result = "var " & result
  elif tfPtrType in t.flags:
    result = "ptr " & result
  elif tfTypeDesc in t.flags:
    result = "typedesc[" & result & "]"

  if t.dimensionality.isSome():
    result = "array[" & $t.dimensionality.unsafeGet() & ", " & result & "]"


func innerDependencies*(t: GodotType; hints: var set[DependencyHint]): OrderedSet[string] =
  result = initOrderedSet[string]()

  let rt = t.metaType.get(t.rawType)

  if tfRefType in t.flags:
    hints.incl dhCoreClasses

  if rt.startsWith("enum::") or rt.startsWith("bitfield::"):
    # enums and bitfields are the same for our purposes
    let te = rt.parseTypedEnum()

    if te.class.isSome():
      result.incl te.class.unsafeGet()
    else:
      hints.incl dhGlobalEnums

  elif rt.startsWith("typedarray::"):
    result.incl "TypedArray"
    result.incl rt[12..^1]

  else:
    result.incl rt


func isNativeClass*(className: string): bool =
  case className
    of "int", "bool", "float", "double", "float64", "int32", "int64", "uint64": true

    # Oddities from classes and native structs
    of "const void*", "uint64_t": true
    else: false

func autogenDisclaimer*(): string =
  "# Generated by nodot on " & CompileDate & "T" & CompileTime & "Z\n" &
  "# Tamper at your own leisure but know that changes may get wiped out\n\n"

func isNativeClass*(class: BuiltinClassDefinition): bool =
  class.name.isNativeClass()

func isOperator(id: string): bool =
  for c in id:
    if c.isAlphaAscii(): return false

  return true

func safeIdent*(id: string): string =
  # Nim identifiers may not start with "_", which some protected identifiers in
  # C like languages like to do

  if id == "result": # very reserved in functions.
    return "p_result"

  let canonicalId = if id.startsWith('_'):
    "prot" & id
  else:
    id

  if canonicalId.isReservedWord or canonicalId.isOperator:
    return "`" & canonicalId & "`"
  else:
    return canonicalId

func safeImport*(id: string): string =
  if id.isReservedWord:
    return '"' & id & '"'
  else:
    return id

proc isOpaque*(class: BuiltinClassDefinition): bool =
  # It's either opaque one all configs or on none.
  for cfgClass in apiDef.builtin_class_member_offsets[0].classes:
    if cfgClass.name == class.name:
      return false

  return true

proc isClassType*(name: string): bool =
  name in apiDef.classTypes

func isSimpleType*(k: ConstantDefinition): bool =
  k.type.isNativeClass()

#func actualType(arg: ClassMethodReturn | FunctionArgument): string =
#  arg.meta.get(arg.`type`)

func indent*(code: string; n: int = 1): string =
  let indentPad = repeat("  ", n)

  indentPad & code
    # Indent after newline
    .replace("\n", "\n" & indentPad)

    # Strip trailing whitespace
    .strip(false, true, {' '})

    # Trim only-indent lines
    .replace("\n" & indentPad & "\n", "\n\n")


## Dependency tracking
type
  SomeDependant* = BuiltinClassDefinition | ClassDefinition |
    seq[FunctionDefinition] | seq[NativeStructure]

  ClassDependencies* = object
    builtins*: OrderedSet[string]
    classes*: OrderedSet[string]
    native_structs*: OrderedSet[string]

  DependencyResolveOption* = enum
    # Builtins + Classes
    roProperties
    roMethods

    # Builtins
    roStructFields
    roConstructors
    roIndexes
    roOperators

    # For Classes
    roParentClass

proc referencedTypes*(
    def: SomeDependant;
    opt: set[DependencyResolveOption];
    hints: var set[DependencyHint]): OrderedSet[string] =
  var topLevel = initOrderedSet[GodotType]()

  when def is BuiltinClassDefinition:
    # Reference fields
    if roStructFields in opt:
      for fields, _ in pairs def.memberGroups():
        for field in fields:
          topLevel.incl field.fromField(def)

        break

    # Reference all parameter types in all constructors
    if roConstructors in opt:
      for ctor in def.constructors:
        for arg in ctor.arguments.get(@[]):
          topLevel.incl arg.fromParameter(def)

    # Reference members
    if roProperties in opt:
      for member in def.members.get(@[]):
        topLevel.incl member.fromProperty(def)

    if roIndexes in opt:
      # Reference index
      if def.indexing_return_type.isSome():
        topLevel.incl def.indexing_return_type.unsafeGet().fromVarious(def)

        if def.is_keyed: # No need to import anything for the alternative
          topLevel.incl "Variant".fromVarious(def)

    if roOperators in opt:
      # Reference operator
      for oper in def.operators:
        topLevel.incl oper.return_type.fromVarious(def)

        if oper.right_type.isSome():
          topLevel.incl oper.right_type.unsafeGet().fromVarious(def)

  when def is BuiltinClassDefinition or def is ClassDefinition:
    if roMethods in opt:
      for meth in def.methods.get(@[]):
        if not meth.is_static:
          topLevel.incl fromSelf(def)

        when def is BuiltinClassDefinition:
          if meth.return_type.isSome():
            topLevel.incl meth.return_type.unsafeGet().fromReturn(def)

        elif def is ClassDefinition:
          if meth.return_value.isSome():
            topLevel.incl meth.return_value.unsafeGet().fromReturn(def)

        for param in meth.arguments.get(@[]):
          topLevel.incl param.fromParameter(def)

  when def is seq[FunctionDefinition]:
    for fn in def:
      if fn.return_type.isSome():
        topLevel.incl fn.return_type.unsafeGet().fromReturn(fn)

      for arg in fn.arguments.get(@[]):
        topLevel.incl arg.fromParameter(fn)

  when def is seq[NativeStructure]:
    for nat in def:
      for field in nat.format.split(";"):
        var fieldName: string
        var fieldType: GodotType

        field.parseCtype(fieldName, fieldType)

        topLevel.incl fieldType

  # Resolve inner dependencies
  result = initOrderedSet[string]()

  # I broke overload resolution somehow, so we explicitely refer to
  # sets.items()
  for referenced in sets.items(topLevel):
    for inner in sets.items(referenced.innerDependencies(hints)):
      result.incl inner

  when def is BuiltinClassDefinition or def is ClassDefinition:
    result.excl def.name

let nativeTypes = toHashSet [
  "int", "float", "double", "pointer", "real_t", "bool",
  "cstring",

  # Very little consistency in the JSON data.
  "uint8_t", "uint16_t", "uint32_t", "uint64_t",
  "uint8", "uint16", "uint32", "uint64",

  "int8_t", "int16_t", "int32_t", "int64_t",
  "int8", "int16", "int32", "int64"
]

proc splitClassDependencies*(deps: OrderedSet[string]): ClassDependencies =
  # TODO: cache
  result.builtins = initOrderedSet[string]()
  result.classes = initOrderedSet[string]()
  result.native_structs = initOrderedSet[string]()

  for unsorted in deps:
    if unsorted in apiDef.builtinClassTypes:
      result.builtins.incl unsorted

    elif unsorted in apiDef.nativeStructTypes:
      result.native_structs.incl unsorted

    elif unsorted notin nativeTypes:
      # Not in builtins, native structs or a totally native type => class
      result.classes.incl unsorted


# Helpers to group equivalent members and sizes into `when ...`-able groups.
proc memberGroups*(class: BuiltinClassDefinition): OrderedTable[seq[MemberOffset], seq[string]] =
  result = initOrderedTable[seq[MemberOffset], seq[string]]()

  for cfg in apiDef.builtin_class_member_offsets:
    for cfgClass in cfg.classes:
      if cfgClass.name == class.name:
        let cleanedMembers = collect(newSeq()):
          for mem in cfgClass.members:
            # We don't care about the offset for the groupings because the
            # the compiler will do that for us.
            MemberOffset(member: mem.member, meta: mem.meta, offset: 0)

        if cleanedMembers notin result:
          result[cleanedMembers] = @[]

        result[cleanedMembers] &= cfg.build_configuration

proc sizeGroups*(className: string): OrderedTable[int, seq[string]] =
  result = initOrderedTable[int, seq[string]]()

  for cfg in apiDef.builtin_class_sizes:
    for cfgClass in cfg.sizes:
      if cfgClass.name == className:
        if cfgClass.size notin result:
          result[cfgClass.size] = @[]

        result[cfgClass.size] &= cfg.build_configuration

proc sizeGroups*(class: BuiltinClassDefinition): OrderedTable[int, seq[string]] =
  return class.name.sizeGroups()

func isPointerType*(class: BuiltinClassDefinition): bool =
  # Small optimization so we can render some opaque types as "pointer"
  case class.name
    of "String", "Dictionary", "Array", "StringName", "NodePath": true
    else: false

proc isSingleton*(class: ClassDefinition): bool =
  for sngl in apiDef.singletons:
    if sngl.name == class.name:
      return true

func getMethod*(class: ClassDefinition; meth: string): Option[ClassMethodDefinition] =
  for m in class.methods.get(@[]):
    if m.name == meth:
      return some m

func copyCtorIdx*(builtin: BuiltinClassDefinition): int =
  for constructor in builtin.constructors:
    if constructor.arguments.isSome() and
        len(constructor.arguments.unsafeGet()) == 1 and
        constructor.arguments.unsafeGet()[0].`type` == builtin.name:

      return constructor.index

func definesMethod*(class: ClassDefinition; meth: string): bool =
  class.getMethod(meth).isSome()

# Style conventions
func deriveCtorName*(clsName: string): string =
  "new" & clsName

func deriveDtorName*(clsName: string): string =
  "destroy"


# Purely visual rendering things below
type FunctionRenderOptions = enum
  roNotExported,
  roFunc,
  roAnonymous

type
  CombinedArgs = tuple
    bindings: seq[string]
    `type`: GodotType


proc renderImportList*(
    dependant: SomeDependant;
    options: set[DependencyResolveOption];
    builtinsPrefix, classPrefix, enumPath, nativesPath, ignore: Option[string] = none string): string =

  result = ""

  var outHints: set[DependencyHint] = {}
  var references = dependant.referencedTypes(options, outHints)

  if ignore.isSome():
    references.excl ignore.unsafeGet()

  let sorted = references.splitClassDependencies()

  # Update our cache
  when compiles(dependant.name):
    if dependant.name notin apiDef.typeDeps:
      apiDef.typeDeps[dependant.name] = initOrderedSet[string]()

    for reference in sets.items(references):
      apiDef.typeDeps[dependant.name].incl reference
      apiDef.typeDeps[dependant.name].incl reference.moduleName()

  if enumPath.isSome():
    if dhGlobalEnums in outHints:      result &= "import " & enumPath.get() & "\n"

  if dhCoreClasses in outHints:        result &= "import ../ref_helper\n"

  if nativesPath.isSome():
    if len(sorted.native_structs) > 0: result &= "import " & nativesPath.get() & "\n"

  if builtinsPrefix.isSome() and len(sorted.builtins) > 0:
    if len(result) > 0:
      result &= "\n"

    result &= "import\n"

    for i, builtin in enumerate(sets.items(sorted.builtins)):
      result &= "  " & builtinsPrefix.unsafeGet() & builtin.moduleName().safeImport()
      result &= (if i < len(sorted.builtins) - 1: ",\n" else: "\n")


  if classPrefix.isSome() and len(sorted.classes) > 0:
    if len(result) > 0:
      result &= "\n"

    result &= "import\n"

    for i, class in enumerate(sets.items(sorted.classes)):
      result &= "  " & classPrefix.unsafeGet() & class.moduleName().safeImport()
      result &= (if i < len(sorted.classes) - 1: ",\n" else: "\n")

  if len(result) > 0:
    result &= "\n"

proc renderImportList*(
    dependant: SomeDependant;
    options: set[DependencyResolveOption];
    builtinsPrefix, classPrefix, enumPath, nativesPath: string;
    ignore: Option[string] = none string): string =
  renderImportList(dependant, options,
    some builtinsPrefix,
    some classPrefix,
    some enumPath,
    some nativesPath,
    ignore)

proc renderImportList*(
    dependant: SomeDependant;
    options: set[DependencyResolveOption];
    builtinsPrefix, classPrefix, enumPath: string): string =
  renderImportList(dependant, options,
    some builtinsPrefix,
    some classPrefix,
    some enumPath,
    none string,
    none string)

proc renderGetter*(def: ClassDefinition; property: ClassPropertyDefinition): string =
  let getterMethod = def.getMethod(property.getter)

  "TBD"

proc renderSetter*(def: ClassDefinition; property: ClassPropertyDefinition): string =
  let setterMethod = def.getMethod(property.getter)

  "TBD"

proc renderArgs(args: openArray[CombinedArgs]): string =
  result = "("

  for i, arg in enumerate(args):
    result &= arg.bindings.join(", ") & ": " & arg.`type`.render()

    if i < args.len - 1:
      result &= "; "

  result &= ")"

proc renderDtor*(def: BuiltinClassDefinition): string =
  &"proc destroy*(self: sink {def.name})"

proc render*(ctor: ConstructorDefinition, def: BuiltinClassDefinition): string =
  var args = newSeq[CombinedArgs]()

  let selfType = fromSelf(def)

  #args &= (bindings: @["_"], `type`: "typedesc[" & selfType.renderType() & "]")

  for defArg in ctor.arguments.get(@[]):
    let defArgType = defArg.fromParameter(def)

    if len(args) == 0 or args[^1].`type` != defArgType:
      args &= (
        bindings: @[defArg.name.safeIdent()],
        `type`: defArgType)
    else:
      args[^1].bindings &= defArg.name.safeIdent()

  result = "proc " & def.name.deriveCtorName() & "*" & args.renderArgs() & ": " & selfType.render()

proc render*(meth: ClassMethodDefinition, def: ClassDefinition | BuiltinClassDefinition; qualifyEnums: bool = true): string =
  # TODO:
  #   - Default values
  #
  var args = newSeq[CombinedArgs]()

  let selfType = fromSelf(def)

  if meth.is_static:
    var tmp = selfType

    tmp.flags.excl tfRefType

    args &= (bindings: @["_"], `type`: tmp.asTypeDesc())
  else:
    if meth.is_const or def is ClassDefinition:
      args &= (bindings: @["self"], `type`: selfType)
    else:
      args &= (bindings: @["self"], `type`: selfType.asVarType())

  for defArg in meth.arguments.get(@[]):
    let defArgType = defArg.fromParameter(def)
    var paramArg = defArg.name.safeIdent()

    # We need to hack around a bit in case a method defines a parameter with the same
    # name as a dependency prefix that may be used within the same prototype.
    if paramArg in apiDef.typeDeps[def.name] or paramArg == def.name.moduleName():
      paramArg = "p_" & paramArg

    if len(args) == 1 or args[^1].`type` != defArgType:
      args &= (
        bindings: @[paramArg],
        `type`: defArgType)
    else:
      args[^1].bindings &= paramArg

  if meth.is_vararg:
    args &= (bindings: @["args"], `type`: def.makeVarArgsParam())

  if def is ClassDefinition:
    result = "proc " & meth.name.safeIdent() & "*" & args.renderArgs()
  else:
    result = "proc " & meth.name.safeIdent() & "*" & args.renderArgs()

  if meth.return_value.isSome():
    let ret = meth.return_value.unsafeGet().fromReturn(def)

    result &= ": " & ret.render()

proc render*(meth: MethodDefinition, def: BuiltinClassDefinition): string =
  # A builtin class method is just a simpler class method.
  let asClassMethod = ClassMethodDefinition(
    name: meth.name,
    is_static: meth.is_static,
    is_const: meth.is_const,
    is_vararg: meth.is_vararg,
    is_virtual: false,
    hash: meth.hash,
    return_value: meth.return_type.map(proc(ty: string): ClassMethodReturn =
      result.`type` = ty
      result.meta = none string),

    arguments: meth.arguments
  )

  return asClassMethod.render(def, false)

proc render*(fn: FunctionDefinition; opts: set[FunctionRenderOptions] = {}): string =
  result = if roFunc in opts: "func" else: "proc"

  if roAnonymous notin opts:
    result &= " " & fn.name.safeIdent()

    if roNotExported notin opts:
      result  &= "*"

  var args = newSeq[CombinedArgs]()

  for defArg in fn.arguments.get(@[]):
    let defArgType = defArg.fromParameter(fn)

    if len(args) == 0 or args[^1].`type` != defArgType:
      args &= (
        bindings: @[defArg.name.safeIdent()],
        `type`: defArgType)
    else:
      args[^1].bindings &= defArg.name.safeIdent()

  if fn.is_vararg:
    args &= (bindings: @["args"], `type`: fn.makeVarArgsParam())

  result &= args.renderArgs()

  if fn.return_type.get("void") != "void":
    let ret = fromReturn(fn.return_type.unsafeGet(), fn)

    result &= ": " & ret.render()


proc render*(op: OperatorDefinition; left: string): string =
  let name = case op.name
    of "unary-": "-"
    of "unary+": "+"
    else: op.name

  var args = @[FunctionArgument(name: "lhs", `type`: left)]

  if op.right_type.isSome():
    args &= FunctionArgument(name: "rhs", `type`: op.right_type.unsafeGet())

  let dummyFunc = FunctionDefinition(
    name: name,
    return_type: some op.return_type,
    category: "operator",
    is_vararg: false,
    hash: 0,
    arguments: some args)

  return dummyFunc.render()

func splitTitleCase(tcs: string): seq[string] =
  result = @[$tcs[0]]

  for c in tcs[1..^1]:
      if result[^1][^1].isLowerAscii() and c.isUpperAscii():
          result &= $c
      else:
          result[^1] &= $c

proc derivePrefix(enu: EnumDefiniton; pfxLen: int = 3): string =
  var prefixCache {.global.} = initTable[EnumDefiniton, string]()

  if enu in prefixCache:
    return prefixCache[enu]

  result = ""

  let parts = enu.name.splitTitleCase()

  var i = 0

  while i < pfxLen:
    if i >= len(parts):
      break
    elif len(parts[i]) == 0:
      continue

    if len(parts) - 1 <= i:
      result &= parts[^1][0..min(len(parts[^1]) - 1, pfxLen - i - 1)].toLowerAscii()
      break
    else:
      result &= parts[i][0].toLowerAscii()

      inc i

  prefixCache[enu] = result

proc cleanName*(value: EnumValue; parent: EnumDefiniton; prefixEnumAbbr: bool = true): string =
  result = case parent.name:
    of "Key": value.name[len("KEY_")..^1]
    of "Axis": value.name[len("AXIS_")..^1]
    of "MouseButton": value.name[len("MOUSE_BUTTON_")..^1]
    of "MouseButtonMask": value.name[len("MOUSE_BUTTON_MASK_")..^1]
    of "JoyButton": value.name[len("JOY_BUTTON_")..^1]
    of "JoyAxis": value.name[len("JOY_AXIS_")..^1]
    of "MIDIMessage": value.name[len("MIDI_MESSAGE_")..^1]
    of "PropertyHint": value.name[len("PROPERTY_HINT_")..^1]
    of "PropertyUsageFlags": value.name[len("PROPERTY_USAGE_")..^1]
    of "MethodFlags":
      if value.name == "METHOD_FLAGS_DEFAULT": "DEFAULT"
      else: value.name[len("METHOD_FLAG_")..^1]

    of "Error":
      if value.name.startsWith("ERR_"):
        value.name[len("ERR_")..^1]
      else:
        value.name

    else: value.name

  var parts = result.split('_')

  # Transform to camelCase
  for i in 0..high(parts):
    parts[i] = parts[i][0].toUpperAscii() & parts[i][1..^1].toLowerAscii()

  # If we want to prefix, make TitleCase
  if not prefixEnumAbbr:
    parts[0] = parts[0].toLowerAscii()

  result = parts.join()

  # Append prefix, maybe
  if prefixEnumAbbr:
    result = parent.derivePrefix() & result