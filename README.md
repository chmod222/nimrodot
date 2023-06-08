# GDExtension Nim Bindings
This project is a work in progress implementation / proof of concept of the
Godot 4 GDExtension API.

Note that this is not yet usable for actual development.

## Status:
  - [x] Library initialization / deinitialization hooks

  - Bindings of all builtin classes (`Variant`, `Vector2`, ...)
    - [x] Construction, deconstruction
    - [x] Methods
    - [x] Properties
    - [x] Index (keyed and positional)
    - [x] Fixed-arity and variadic calls

  - Bindings of all utility functions
    - [x] Fixed-arity and variadic calls

  - Godot classes:
    - [x] Basic usage
    - [x] Destruction
    - [x] Calling methods
      - Works in principle, but further testing required to make sure every case works.

  - Registering custom classes:
    - [x] Construction, Destruction hooks
    - Dynamic Properties (`.get`, `.set` in Godot)
      - [x] Get/Set
      - [x] Query revertible status and revert value
      - [x] Query property List
    - Methods
      - [ ] Virtual
        - Fundamentals implemented, missing usability
      - [x] Static
      - [x] Instance
      - [x] Bindcall
      - [x] ptrcall
      - [x] Variadic
    - [x] Builtin Properties (`.property_name` in Godot)
      - Lower level exposure implemented, higher level wrapper missing
    - [X] Signals
      - Should work, still needs testing

## What somewhat works:
  - TypedArray[T] does not enforce the `T` or `Typed` part so far, but with some self discipline it
    will work until compile time enforcements are implemented.

  - Memory management
    - `RefCounted` (and it's associated Ref[T] wrapper) and manually managed objects *should* work,
       but need testing to iron out any lurking issues. Objects not deriving from `RefCounted` need
       some discipline to work with for now, until a nicer abstraction over them makes life easier.

## What does not work:
  - Most likely some other things that can not be tested as of yet. The GDExtension interface is
    very sparsely documented for now and surprises still lurk in some corners where assumption and
    reality drift apart.

## How it works:

Two step auto-generation from the included "contrib/extension_api.json"

    nimble generateApi

This is also called automatically in the pre-install step.

This generates the following modules:

- `nodot/api`: Very high level definitions.
- `nodot/enums`: Global enumerations and bitfields.
- `nodot/utility_functions`: Utility functions.
- `nodot/builtins/types/*` (except `variant`): Builtin class type
- `nodot/builtins/*` (except `variant`): Builtin class procs
- `nodot/classes/types/*`: Godot Classes
- `nodot/classes/*`: Godot Classes

Most methods are stubbed with various Macros that implement the actual glue
on end-compile, i.e.

```nim
proc lerp*(self: Vector2; to: Vector2; weight: float64): Vector2
  {.gd_builtin_method(Vector2, 4250033116).}
```

These do the job of caching the various function pointers and converting the arguments and are implemented in the `nodot/gdffi` module.

## Usage Example (Proof of Concept)

(A longer and more useful example is contained in the [examples](/examples) folder.

```nim
# If not specified, entry point defaults to "gdext_init"
godotHooks(GDEXTENSION_INITIALIZATION_SCENE):
  # Called for every initialization level
  initialize(level):
    if level == GDEXTENSION_INITIALIZATION_SCENE:
      echo "Hello World from Godot"

      # Dumping some random information for now
      var os: OS = getSingleton[OS]("OS")

      echo "Processor Name: ", os.get_processor_name()

      let fonts = os.get_system_fonts().newVariant()

      var dir = DirAccess.open("res://".newString())
      var files = dir.get_files().newVariant()

      echo fonts
      echo files

  # Called for every initialization level in reverse order
  deinitialize(level):
    echo "Bye World from Godot!"
```
