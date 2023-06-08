import nimrodot
import nimrodot/classdb
import nimrodot/builtins/variant
import nimrodot/builtins/stringname
import nimrodot/builtins/"string"
import nimrodot/classes/node
import nimrodot/classes/refcounted

import std/options
import std/typetraits

type
  # Custom objects *must* be "ptr object". If no "of ..." is specified,
  # a default of "of Object" is assumed. The parent class may be another
  # custom class, but the inheritance chain of custom classes *must* start
  # with any Godot class.
  ExportedType {.customClass.} = ptr object of RefCounted
    someField: int

  # Likewise: {.classEnum.}
  SomeFlags {.classBitfield: ExportedType.} = enum
    Flag_A = 1
    Flag_B = 2
    Flag_C = 4
    Flag_D = 8

# Unnamed constants
const
  FOO_CONST* {.constant: ExportedType.} = 3
  BAR_CONST* {.constant: ExportedType.} = 5

# Signals are registered as annotated prototypes
proc something_happened(wasItImportant: bool) {.signal: ExportedType.}
proc something_else_happened() {.signal: ExportedType.}

# Virtuals are "implemented" by overriding the naked vtable for now
var vtable: pointerBase (typeOf (gdVTablePointer(Node))) = gdVTablePointer(Node)[]

# Override _process for example
vtable.v_process = proc(self: Node; delta: float64) =
  discard

# Needed internally
proc gdVTablePointer*(_: typedesc[ExportedType]): auto = unsafeAddr vtable


# Invoked by Godot on instance creation
proc initType(self: ExportedType) {.ctor.} =
  self.someField = 1

# Invoked by Godot on instance destruction
proc destroyType(self: ExportedType) {.dtor.} =
  discard


# Default parameters supported, as well as varargs[Variant]
proc do_something*(self: ExportedType; param_a: String, param_b, param_c: int = 0): int16 {.classMethod.} =
  # ...
  42

# Methods for properties
proc set_field(self: ExportedType; newVal: int) {.classMethod.} =
  self.someField = newVal

proc get_field(self: ExportedType): int {.classMethod.} =
  self.someField

# Static method, renamed via {.name.}.
proc call_stat(a: int) {.staticMethod: ExportedType, name: "static_method".} =
  discard

# Called by Godot to retrieve a default value for a given property.
proc queryRevert(self: ExportedType; property: StringName): Option[Variant] {.revertQuery.} =
  if property == StringName("something"):
    some %true
  else:
    none Variant

# Called by Godot to retrieve a list of all properties
proc queryProperties(self: ExportedType; properties: var seq[GDExtensionPropertyInfo]) {.propertyQuery.} =
  addPropertyInfo[bool](properties, "something")

# Dynamic properties, called for any non statically registered properties
proc getProperty(self: ExportedType; name: StringName): Option[Variant] {.getProperty.} =
  # Discard
  none Variant

proc setProperty(self: ExportedType; name: StringName; value: Variant): bool {.setProperty.} =
  discard

# Notification handler
proc handleNotification(self: ExportedType; what: int) {.notification.} =
  discard

# Main extension entry point. May be called in multiple fashions:
#  - godotHooks()
#  - godotHooks(initLevel)
#  - godotHooks(symbolName)
#  - godotHooks(symbolName, initLevel)
#
# The symbol name controls how the GDExtension entry point is called. This is what needs to be
# specified in the .gdextension file for Godot.
#
# The init level tells Godot how "far" to initialize the extension and can be one of the following:
#  - GDEXTENSION_INITIALIZATION_CORE
#  - GDEXTENSION_INITIALIZATION_SERVERS
#  - GDEXTENSION_INITIALIZATION_SCENE
#  - GDEXTENSION_INITIALIZATION_EDITOR
#  - GDEXTENSION_MAX_INITIALIZATION_LEVEL (same as GDEXTENSION_INITIALIZATION_EDITOR)
#
# The "initialize" and "deinitialize" hooks will be invoked once per level.
#
# Parameters left out assume these default values:
#  - initLevel: GDEXTENSION_MAX_INITIALIZATION_LEVEL
#  - symbolName: gdext_init
godotHooks(GDEXTENSION_INITIALIZATION_SCENE):
  initialize(level):
    echo "Hello World from Godot @ " & $level

    if level == GDEXTENSION_INITIALIZATION_SCENE:
      classdb.register()

      # Missing higher level wrappers for static properties for now, so we manually
      # register them. here.
      classdb.registerPropertyGroup[ExportedType]("General Options", "gen_")
      classdb.registerProperty[ExportedType, int]("gen_field", "set_field", "get_field")

  deinitialize(level):
    echo "Bye World from Godot!" & $level

