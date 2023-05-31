# This is a very boilerplatey part that would poison the readability of the
# classdb module, so we yank it in.

# Property Helpers
func propertyHint(_: typedesc): auto = phiNone
func propertyUsage(_: typedesc): auto = pufDefault

# Type Metadata Helpers
func typeMetaData(_: typedesc): auto = GDEXTENSION_METHOD_ARGUMENT_METADATA_NONE
func typeMetaData(_: typedesc[int8]): auto = GDEXTENSION_METHOD_ARGUMENT_METADATA_INT_IS_INT8
func typeMetaData(_: typedesc[int16]): auto = GDEXTENSION_METHOD_ARGUMENT_METADATA_INT_IS_INT16
func typeMetaData(_: typedesc[int32]): auto = GDEXTENSION_METHOD_ARGUMENT_METADATA_INT_IS_INT32
func typeMetaData(_: typedesc[int64]): auto = GDEXTENSION_METHOD_ARGUMENT_METADATA_INT_IS_INT64
func typeMetaData(_: typedesc[uint8]): auto = GDEXTENSION_METHOD_ARGUMENT_METADATA_INT_IS_UINT8
func typeMetaData(_: typedesc[uint16]): auto = GDEXTENSION_METHOD_ARGUMENT_METADATA_INT_IS_UINT16
func typeMetaData(_: typedesc[uint32]): auto = GDEXTENSION_METHOD_ARGUMENT_METADATA_INT_IS_UINT32
func typeMetaData(_: typedesc[uint64]): auto = GDEXTENSION_METHOD_ARGUMENT_METADATA_INT_IS_UINT64
func typeMetaData(_: typedesc[float32]): auto = GDEXTENSION_METHOD_ARGUMENT_METADATA_REAL_IS_FLOAT
func typeMetaData(_: typedesc[float64 | float]): auto = GDEXTENSION_METHOD_ARGUMENT_METADATA_REAL_IS_DOUBLE

func typeMetaData(_: typedesc[int | uint]): auto =
  if (sizeOf int) == 4:
    GDEXTENSION_METHOD_ARGUMENT_METADATA_INT_IS_INT32
  else:
    GDEXTENSION_METHOD_ARGUMENT_METADATA_INT_IS_INT64

# The variant module and all builtins already declare `variantTypeId` so that
# we can map all manner of types into variants, but we also need to be able
# to go back from a variant type ID into a specific binary type that we then
# may downcast.

# Any numeric gets widened into the largest we could receive and then
# casted back down, as we hope that Godot did respect our metadata.
template mapBuiltinType(_: typedesc[SomeInteger]): auto = int64
template mapBuiltinType(_: typedesc[SomeFloat]): auto = float64

# Objects are all the same on the binary level (as far as GDExt is concerned)
template mapBuiltinType[T: AnyObject](_: typedesc[T]): auto = T

# The builtins just map back to themselves
template mapBuiltinType(_: typedesc[bool]): auto = bool
template mapBuiltinType(_: typedesc[Variant]): auto = Variant

template mapBuiltinType(_: typedesc[Signal]): auto = Signal
template mapBuiltinType(_: typedesc[Callable]): auto = Callable
template mapBuiltinType(_: typedesc[String]): auto = String
template mapBuiltinType(_: typedesc[Quaternion]): auto = Quaternion
template mapBuiltinType(_: typedesc[PackedFloat64Array]): auto = PackedFloat64Array
template mapBuiltinType(_: typedesc[Dictionary]): auto = Dictionary
template mapBuiltinType(_: typedesc[Array]): auto = Array
template mapBuiltinType(_: typedesc[StringName]): auto = StringName
template mapBuiltinType(_: typedesc[Color]): auto = Color
template mapBuiltinType(_: typedesc[PackedStringArray]): auto = PackedStringArray
template mapBuiltinType(_: typedesc[Array]): auto = Array
template mapBuiltinType(_: typedesc[PackedInt32Array]): auto = PackedInt32Array
template mapBuiltinType(_: typedesc[Vector3i]): auto = Vector3i
template mapBuiltinType(_: typedesc[Basis]): auto = Basis
template mapBuiltinType(_: typedesc[NodePath]): auto = NodePath
template mapBuiltinType(_: typedesc[PackedFloat32Array]): auto = PackedFloat32Array
template mapBuiltinType(_: typedesc[RID]): auto = RID
template mapBuiltinType(_: typedesc[Vector2]): auto = Vector2
template mapBuiltinType(_: typedesc[Rect2i]): auto = Rect2i
template mapBuiltinType(_: typedesc[PackedVector2Array]): auto = PackedVector2Array
template mapBuiltinType(_: typedesc[AABB]): auto = AABB
template mapBuiltinType(_: typedesc[Vector4]): auto = Vector4
template mapBuiltinType(_: typedesc[Vector4i]): auto = Vector4i
template mapBuiltinType(_: typedesc[Nil]): auto = Nil
template mapBuiltinType(_: typedesc[Vector2i]): auto = Vector2i
template mapBuiltinType(_: typedesc[Plane]): auto = Plane
template mapBuiltinType(_: typedesc[Transform2D]): auto = Transform2D
template mapBuiltinType(_: typedesc[Transform3D]): auto = Transform3D
template mapBuiltinType(_: typedesc[Vector3]): auto = Vector3
template mapBuiltinType(_: typedesc[PackedColorArray]): auto = PackedColorArray
template mapBuiltinType(_: typedesc[PackedVector3Array]): auto = PackedVector3Array
template mapBuiltinType(_: typedesc[PackedByteArray]): auto = PackedByteArray
template mapBuiltinType(_: typedesc[Projection]): auto = Projection
template mapBuiltinType(_: typedesc[Rect2]): auto = Rect2
template mapBuiltinType(_: typedesc[PackedInt64Array]): auto = PackedInt64Array

# If we did not hit any overload, there is a gap in our coverage and we must
# handle that.
template mapBuiltinType[T](_: typedesc[T]) =
  {.error: "generic mapBuiltinType invoked".}

# TODO: We need some more complex type converters. For most of these we can
#       simply blit over whatever Godot gives us, but for things like Ref[T]
#       we need to may need to use ref_get_object and ref_set_object.
func argFromPointer[T](p: GDExtensionConstTypePtr): T =
  copyMem(addr result, p, sizeOf(T))