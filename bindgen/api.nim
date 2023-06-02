import std/[sets, options, tables, json]

type
  Header* = object
    version_major*: int
    version_minor*: int
    version_patch*: int
    version_status*: string
    version_build*: string
    version_full_name*: string

  MemberOffset* = object
    member*: string
    meta*: string
    offset*: int

  ClassSize* = object
    name*: string
    size*: int

  ClassOffsets* = object
    name*: string
    members*: seq[MemberOffset]

  BuiltinClassSizes* = object
    build_configuration*: string
    sizes*: seq[ClassSize]

  BuiltinClassMemberOffsets* = object
    build_configuration*: string
    classes*: seq[ClassOffsets]

  EnumDefiniton* = object
    name*: string
    is_bitfield*: Option[bool]
    values*: seq[EnumValue]

  EnumValue* = object
    name*: string
    value*: int

  FunctionArgument* = object
    name*: string
    `type`*: string
    meta*: Option[string]
    default_value*: Option[string]

  FunctionDefinition* = object
    name*: string
    return_type*: Option[string]
    category*: string
    is_vararg*: bool
    hash*: uint
    arguments*: Option[seq[FunctionArgument]]

  ConstructorDefinition* = object
    index*: int
    arguments*: Option[seq[FunctionArgument]]

  OperatorDefinition* = object
    name*: string
    right_type*: Option[string]
    return_type*: string

  MethodDefinition* = object
    name*: string

    is_vararg*: bool
    is_const*: bool
    is_static*: bool

    return_type*: Option[string]
    hash*: uint
    arguments*: Option[seq[FunctionArgument]]

  ClassMethodReturn* = object
    `type`*: string
    meta*: Option[string]

  #ClassMethodArgument* = object
  #  name*: string
  #  `type`*: string
  #  meta*: Option[string]
  #  default_value*: Option[string]

  ClassMethodDefinition* = object
    name*: string

    is_const*: bool
    is_vararg*: bool
    is_static*: bool
    is_virtual*: bool

    hash*: Option[uint]

    return_value*: Option[ClassMethodReturn]
    arguments*: Option[seq[FunctionArgument]]

  PropertyDefinition* = object
    name*: string
    `type`*: string

  ConstantDefinition* = object
    name*: string
    `type`*: string
    value*: string

  BuiltinClassDefinition* = object
    name*: string
    is_keyed*: bool
    indexing_return_type*: Option[string]
    has_destructor*: bool

    constructors*: seq[ConstructorDefinition]
    operators*: seq[OperatorDefinition]

    members*: Option[seq[PropertyDefinition]]
    methods*: Option[seq[MethodDefinition]]
    enums*: Option[seq[EnumDefiniton]]
    constants*: Option[seq[ConstantDefinition]]

  ClassConstant* = object
    name*: string
    value*: int

  ClassPropertyDefinition* = object
    `type`*: string
    name*: string
    setter*: Option[string]
    getter*: string

  SignalDefinition* = object
    name*: string
    arguments*: Option[seq[FunctionArgument]]

  ClassDefinition* = object
    name*: string
    is_refcounted*: bool
    is_instantiable*: bool
    inherits*: Option[string]
    api_type*: string

    constants*: Option[seq[ClassConstant]]
    enums*: Option[seq[EnumDefiniton]]
    methods*: Option[seq[ClassMethodDefinition]]
    properties*: Option[seq[ClassPropertyDefinition]]
    signals*: Option[seq[SignalDefinition]]

  NativeStructure* = object
    name*: string
    format*: string

  Singleton* = object
    name*: string
    `type`*: string

  ApiDump* = object
    header*: Header

    builtin_classes*: seq[BuiltinClassDefinition]
    builtin_class_sizes*: seq[BuiltinClassSizes]
    builtin_class_member_offsets*: seq[BuiltinClassMemberOffsets]

    global_enums*: seq[EnumDefiniton]

    classes*: seq[ClassDefinition]
    singletons*: seq[Singleton]

    utility_functions*: seq[FunctionDefinition]
    native_structures*: seq[NativeStructure]

  Api* = ref object
    inner: ApiDump

    nativeStructTypes*: HashSet[string]
    builtinClassTypes*: HashSet[string]
    classTypes*: Table[string, ClassDefinition]

    typeDeps*: Table[string, OrderedSet[string]]

proc header*(api: Api): Header = api.inner.header
proc builtin_classes*(api: Api): seq[BuiltinClassDefinition] = api.inner.builtin_classes
proc builtin_class_sizes*(api: Api): seq[BuiltinClassSizes] = api.inner.builtin_class_sizes
proc builtin_class_member_offsets*(api: Api): seq[BuiltinClassMemberOffsets] = api.inner.builtin_class_member_offsets
proc global_enums*(api: Api): seq[EnumDefiniton] = api.inner.global_enums
proc classes*(api: Api): seq[ClassDefinition] = api.inner.classes
proc singletons*(api: Api): seq[Singleton] = api.inner.singletons
proc utility_functions*(api: Api): seq[FunctionDefinition] = api.inner.utility_functions
proc native_structures*(api: Api): seq[NativeStructure] = api.inner.native_structures

proc fill_caches(api: var Api) =
  api.typeDeps = initTable[string, OrderedSet[string]]()

  for native in api.native_structures:
    api.nativeStructTypes.incl native.name

  for builtin in api.builtin_classes:
    api.builtinClassTypes.incl builtin.name

  api.builtinClassTypes.excl "bool"
  api.builtinClassTypes.excl "int"
  api.builtinClassTypes.excl "float"

  api.builtinClassTypes.incl "Variant"
  api.builtinClassTypes.incl "TypedArray"

  for class in api.classes:
    api.classTypes[class.name] = class

proc importApi*(path: string): Api =
  let dump = parseJson(readFile(path)).to(ApiDump)

  result = Api(inner: dump)
  result.fill_caches()
