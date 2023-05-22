# GDExtension Nim Bindings
This project is a work in progress implementation / proof of concept of the
Godot 4 GDExtension API.

Note that this is not yet usable for actual development.

## What works:
  - Library initialization / deinitialization hooks
  - Bindings of all builtin classes (`Variant`, `Vector2`, ...)
    - Construction, deconstruction
    - Methods
    - Properties
    - Index (keyed and positional)
    - Fixed-arity and variadic calls

  - Bindings of all utility functions
    - Fixed-arity and variadic calls

  - Proper Godot classes:
    - Usage if you get a pointer to one
    - Destruction

## What does not work:
  - Builtin and Proper classes:
    - Construction
    - Memory management (leaks like a sieve except for trivial cases)
    - Most likely some other things that can not be tested as of yet

  - Registering custom classes

Most of the exciting stuff is now blocked on actually understanding who, and when, is
responsible for freeing memory and calling destructors (further complicated
by the existence of `RefCounted`) and properly mapping it to Nim. This might
be simple or it might be difficult, unfortunately the only canonical source
of documentation is [godot-cpp](https://github.com/godotengine/godot-cpp) which
involves mentally parsing and understanding a lot of macro heavy C++ and that
is not fun.

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