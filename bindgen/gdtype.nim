import std/[options, strutils, tables]

import ./api
import ./helpers

type
  GodotTypeKind* = enum
    # The type was found in its own declaration
    tkBuiltinClassDef,
    tkClassDef,
    tkEnumDef,

    # The type was found in another place and is a dependency
    tkField,
    tkVarArg,
    tkOther # Anything else that doesn't have special requirements

  GodotTypeFlag* = enum
    tfVarType,
    tfPtrType,
    tfRefType,
    tfTypeDesc

  GodotType* = object
    dependant*: Option[string]
    flags*: set[GodotTypeFlag]
    kind*: GodotTypeKind
    rawType*: string
    metaType*: Option[string]

    # Only used for the native structs which are pretty wildly defined.
    dimensionality*: Option[int]

func asVarType*(t: GodotType): GodotType =
  result = t
  result.flags.incl tfVarType

func asTypeDesc*(t: GodotType): GodotType =
  result = t
  result.flags.incl tfTypeDesc

proc cleanType(t: GodotType): GodotType =
  result = t

  if t.rawType in apiDef.classTypes and apiDef.classTypes[t.rawType].isRefcounted:
    result.flags.incl tfRefType

  # Some special cases.
  if t.rawType == "const void*" or t.rawType == "void*":
    result.rawType = "pointer"
  elif t.rawType == "const uint8_t*":
    result.rawType = "cstring"
  elif t.rawType == "const uint8_t **":
    result.rawType = "cstring"
    result.flags.incl tfPtrType

  elif t.rawType.endsWith('*'):
    result.flags.incl tfPtrType

    result.rawType = t.rawType[0..^2]

  if result.rawType.startsWith("const "):
    # Cannot model "const T*", so we model it to "ptr T"
    result.rawType = result.rawType[6..^1]

proc fromSelf*(def: BuiltinClassDefinition | ClassDefinition | EnumDefiniton): GodotType =
  cleanType GodotType(
    dependant: none string,
    kind: if def is ClassDefinition:
      tkClassDef
    elif def is BuiltinClassDefinition:
      tkBuiltinClassDef
    else:
      tkEnumDef,

    rawType: def.name,
    metaType: none string)

proc fromConst*(k: ConstantDefinition; def: BuiltinClassDefinition | ClassDefinition): GodotType =
  cleanType GodotType(dependant: some def.name, kind: tkOther, rawType: k.`type`, metaType: none string)

proc fromField*(field: MemberOffset; def: BuiltinClassDefinition): GodotType =
  cleanType GodotType(dependant: some def.name, kind: tkField, rawType: field.meta, metaType: none string)

proc fromProperty*(prop: PropertyDefinition; def: BuiltinClassDefinition): GodotType =
  cleanType GodotType(dependant: some def.name, kind: tkOther, rawType: prop.`type`, metaType: none string)

proc fromVarious*(t: string; def: BuiltinClassDefinition): GodotType =
  cleanType GodotType(dependant: some def.name, kind: tkOther, rawType: t, metaType: none string)

proc fromParameter*(arg: FunctionArgument; def: ClassDefinition | BuiltinClassDefinition): GodotType =
  result = cleanType GodotType(dependant: some def.name, kind: tkOther, rawType: arg.`type`, metaType: arg.meta)

proc fromParameter*(arg: FunctionArgument; def: FunctionDefinition): GodotType =
  cleanType GodotType(dependant: none string, kind: tkOther, rawType: arg.`type`, metaType: arg.meta)

proc fromReturn*(ret: string; def: BuiltinClassDefinition | FunctionDefinition): GodotType =
  let dep = if def is MethodDefinition:
      some def.name
    else:
      none string

  result = cleanType GodotType(
    dependant: dep,
    kind: tkOther,
    rawType: ret,
    metaType: none string)


proc fromReturn*(ret: ClassMethodReturn; def: ClassDefinition | BuiltinClassDefinition): GodotType =
  cleanType GodotType(dependant: some def.name, kind: tkOther, rawType: ret.`type`, metaType: ret.meta)


func parseCtype*(raw: string; ident: var string; outType: var GodotType) =
  var parts = raw.split(' ')
  var typBase = parts[0]

  if "::" in typBase:
    typBase = "enum::" & typBase.replace("::", ".")

  outType = GodotType(dependant: none string, kind: tkOther, rawType: typBase, metaType: none string)
  ident = parts[1]

  if ident.startsWith('*'):
    outType.flags.incl tfPtrType
    ident = ident[1..^1]

  if ident.endsWith(']'):
    let pos = ident.find('[')
    let dim = parseInt ident[pos + 1..^2]

    ident = ident[0..pos - 1]

    outType.dimensionality = some dim

proc makeVarArgsParam*(def: ClassDefinition | BuiltinClassDefinition | FunctionDefinition): GodotType =
  let dep = when compiles(def.name):
    some def.name
  else:
    none string

  cleanType GodotType(
    dependant: dep,
    kind: tkVarArg,
    rawType: "varargs[Variant, newVariant]",
    metaType: none string)