# Builtin Class Variant (defined manually)
import ../../ffi
import ../../api

import ../../interface_ptrs

type
  Variant* = object
    opaque: array[variantSize, byte]

proc `=destroy`(v: var Variant) =
  gdInterfacePtr.variant_destroy(unsafeAddr v)

proc `=copy`(dest: var Variant; source: Variant) =
  `=destroy`(dest)
  dest.wasMoved()

  gdInterfacePtr.variant_new_copy(addr dest, unsafeAddr source)

# Enums
type
  Type* {.size: sizeof(cint).} = enum
    vtyNil = GDEXTENSION_VARIANT_TYPE_NIL,
    vtyBool = GDEXTENSION_VARIANT_TYPE_BOOL,
    vtyInt = GDEXTENSION_VARIANT_TYPE_INT,
    vtyFloat = GDEXTENSION_VARIANT_TYPE_FLOAT,
    vtyString = GDEXTENSION_VARIANT_TYPE_STRING,
    vtyVector2 = GDEXTENSION_VARIANT_TYPE_VECTOR2,
    vtyVector2i = GDEXTENSION_VARIANT_TYPE_VECTOR2I,
    vtyRect2 = GDEXTENSION_VARIANT_TYPE_RECT2,
    vtyRect2i = GDEXTENSION_VARIANT_TYPE_RECT2I,
    vtyVector3 = GDEXTENSION_VARIANT_TYPE_VECTOR3,
    vtyVector3i = GDEXTENSION_VARIANT_TYPE_VECTOR3I,
    vtyTransform2d = GDEXTENSION_VARIANT_TYPE_TRANSFORM2D,
    vtyVector4 = GDEXTENSION_VARIANT_TYPE_VECTOR4,
    vtyVector4i = GDEXTENSION_VARIANT_TYPE_VECTOR4I,
    vtyPlane = GDEXTENSION_VARIANT_TYPE_PLANE,
    vtyQuaternion = GDEXTENSION_VARIANT_TYPE_QUATERNION,
    vtyAABB = GDEXTENSION_VARIANT_TYPE_AABB,
    vtyBasis = GDEXTENSION_VARIANT_TYPE_BASIS,
    vtyTransform3D = GDEXTENSION_VARIANT_TYPE_TRANSFORM3D,
    vtyProjection = GDEXTENSION_VARIANT_TYPE_PROJECTION,
    vtyColor = GDEXTENSION_VARIANT_TYPE_COLOR,
    vtyStringName = GDEXTENSION_VARIANT_TYPE_STRING_NAME,
    vtyNodePath = GDEXTENSION_VARIANT_TYPE_NODE_PATH,
    vtyRID = GDEXTENSION_VARIANT_TYPE_RID,
    vtyObject = GDEXTENSION_VARIANT_TYPE_OBJECT,
    vtyCallable = GDEXTENSION_VARIANT_TYPE_CALLABLE,
    vtySignal = GDEXTENSION_VARIANT_TYPE_SIGNAL,
    vtyDictionary = GDEXTENSION_VARIANT_TYPE_DICTIONARY,
    vtyArray = GDEXTENSION_VARIANT_TYPE_ARRAY,
    vtyPackedByteArray = GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY,
    vtyPackedInt32Array = GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY,
    vtyPackedInt64Array = GDEXTENSION_VARIANT_TYPE_PACKED_INT64_ARRAY,
    vtyPackedFloat32Array = GDEXTENSION_VARIANT_TYPE_PACKED_FLOAT32_ARRAY,
    vtyPackedFloat64Array = GDEXTENSION_VARIANT_TYPE_PACKED_FLOAT64_ARRAY,
    vtyPackedStringArray = GDEXTENSION_VARIANT_TYPE_PACKED_STRING_ARRAY,
    vtyPackedVector2Array = GDEXTENSION_VARIANT_TYPE_PACKED_VECTOR2_ARRAY,
    vtyPackedVector3Array = GDEXTENSION_VARIANT_TYPE_PACKED_VECTOR3_ARRAY,
    vtyPackedColorArray = GDEXTENSION_VARIANT_TYPE_PACKED_COLOR_ARRAY

  CallErrorType* {.size: sizeof(cint).} = enum
    vceOk = GDEXTENSION_CALL_OK,
    vceInvalidMethod = GDEXTENSION_CALL_ERROR_INVALID_METHOD,
    vceInvalidArgument = GDEXTENSION_CALL_ERROR_INVALID_ARGUMENT,
    vceTooManyArguments = GDEXTENSION_CALL_ERROR_TOO_MANY_ARGUMENTS,
    vceTooFewArguments = GDEXTENSION_CALL_ERROR_TOO_FEW_ARGUMENTS,
    vceInstanceIsNull = GDEXTENSION_CALL_ERROR_INSTANCE_IS_NULL,
    vceMethodNotConst = GDEXTENSION_CALL_ERROR_METHOD_NOT_CONST

func variantTypeId*(_: typedesc[Variant]): GDExtensionVariantType =
  GDEXTENSION_VARIANT_TYPE_NIL

func variantTypeId*(_: typedesc[SomeInteger]): GDExtensionVariantType =
  GDEXTENSION_VARIANT_TYPE_INT

func variantTypeId*(_: typedesc[SomeFloat]): GDExtensionVariantType =
  GDEXTENSION_VARIANT_TYPE_FLOAT

func variantTypeId*(_: typedesc[bool]): GDExtensionVariantType =
  GDEXTENSION_VARIANT_TYPE_BOOL

import ../../classes/types/"object"

type
  AnyObject* = concept var t
    t of Object

func variantTypeId*[T: AnyObject](_: typedesc[T]): GDExtensionVariantType =
  GDEXTENSION_VARIANT_TYPE_OBJECT

# The variant module and all builtins already declare `variantTypeId` so that
# we can map all manner of types into variants, but we also need to be able
# to go back from a variant type ID into a specific binary type that we then
# may downcast.

import ../types

# Any numeric gets widened into the largest we could receive and then
# casted back down, as we hope that Godot did respect our metadata.
template mapBuiltinType*(_: typedesc[SomeInteger]): auto = int64
template mapBuiltinType*(_: typedesc[SomeFloat]): auto = float64

# Objects are all the same on the binary level (as far as GDExt is concerned)
template mapBuiltinType*[T: AnyObject](_: typedesc[T]): auto = T

# The builtins just map back to themselves
template mapBuiltinType*(_: typedesc[bool]): auto = bool
template mapBuiltinType*(_: typedesc[Variant]): auto = Variant

template mapBuiltinType*(_: typedesc[Nil | void]): auto = Nil
template mapBuiltinType*(_: typedesc[Signal]): auto = Signal
template mapBuiltinType*(_: typedesc[Callable]): auto = Callable
template mapBuiltinType*(_: typedesc[String]): auto = String
template mapBuiltinType*(_: typedesc[Quaternion]): auto = Quaternion
template mapBuiltinType*(_: typedesc[PackedFloat64Array]): auto = PackedFloat64Array
template mapBuiltinType*(_: typedesc[Dictionary]): auto = Dictionary
template mapBuiltinType*(_: typedesc[StringName]): auto = StringName
template mapBuiltinType*(_: typedesc[Color]): auto = Color
template mapBuiltinType*(_: typedesc[PackedStringArray]): auto = PackedStringArray
template mapBuiltinType*(_: typedesc[Array]): auto = Array
template mapBuiltinType*(_: typedesc[PackedInt32Array]): auto = PackedInt32Array
template mapBuiltinType*(_: typedesc[Vector3i]): auto = Vector3i
template mapBuiltinType*(_: typedesc[Basis]): auto = Basis
template mapBuiltinType*(_: typedesc[NodePath]): auto = NodePath
template mapBuiltinType*(_: typedesc[PackedFloat32Array]): auto = PackedFloat32Array
template mapBuiltinType*(_: typedesc[RID]): auto = RID
template mapBuiltinType*(_: typedesc[Vector2]): auto = Vector2
template mapBuiltinType*(_: typedesc[Rect2i]): auto = Rect2i
template mapBuiltinType*(_: typedesc[PackedVector2Array]): auto = PackedVector2Array
template mapBuiltinType*(_: typedesc[AABB]): auto = AABB
template mapBuiltinType*(_: typedesc[Vector4]): auto = Vector4
template mapBuiltinType*(_: typedesc[Vector4i]): auto = Vector4i
template mapBuiltinType*(_: typedesc[Nil]): auto = Nil
template mapBuiltinType*(_: typedesc[Vector2i]): auto = Vector2i
template mapBuiltinType*(_: typedesc[Plane]): auto = Plane
template mapBuiltinType*(_: typedesc[Transform2D]): auto = Transform2D
template mapBuiltinType*(_: typedesc[Transform3D]): auto = Transform3D
template mapBuiltinType*(_: typedesc[Vector3]): auto = Vector3
template mapBuiltinType*(_: typedesc[PackedColorArray]): auto = PackedColorArray
template mapBuiltinType*(_: typedesc[PackedVector3Array]): auto = PackedVector3Array
template mapBuiltinType*(_: typedesc[PackedByteArray]): auto = PackedByteArray
template mapBuiltinType*(_: typedesc[Projection]): auto = Projection
template mapBuiltinType*(_: typedesc[Rect2]): auto = Rect2
template mapBuiltinType*(_: typedesc[PackedInt64Array]): auto = PackedInt64Array

# If we did not hit any overload, there is a gap in our coverage and we must
# handle that.
template mapBuiltinType*[T](_: typedesc[T]) =
  {.error: "generic mapBuiltinType invoked: " & $type(T).}

template maybeDowncast*[U](val: auto): U =
  # There's no harm to convert T to T, but it does get spammy with compiler hints
  when typeOf(val) is U:
    val
  else:
    U(val)