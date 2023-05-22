# Package

version       = "0.1.0"
author        = "chmod222"
description   = "Nim GDExtension Bindings"
license       = "MIT"

# Dependencies

requires "nim >= 1.6.3"

task generateApi, "Generate the Godot API interface":
  exec("nim r bindgen/bindgen.nim")

before install:
  generateApiTask()
