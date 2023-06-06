# Builtin Class TypedArray[T]
import ../../ffi
import ../types/"array"

type
  # For now
  TypedArray*[T] = Array

func variantTypeId*(_: typedesc[Array]): GDExtensionVariantType =
  cast[GDExtensionVariantType](28)
