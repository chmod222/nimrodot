type
  Ref*[T] = object
    ## A managed reference to a Godot class (extension class or user defined).
    reference: T

  Owned*[T] = object
    ## A managed, unique reference to a Godot class (extension class or user defined).
    reference: T

import ./interface_ptrs
import ./utils
import ./ffi
import ./builtins/types/stringname
import ./classes/types/"object"

# Re-declare these so we don't have to cyclic import refcounted.nim and gdffi.
# XXX: KEEP IN SYNC.
proc getClassMethodBindPtr(cls, meth: static[string]; hash: static[int64]): GDExtensionMethodBindPtr =
  var gdClassName = cls.toGodotStringName()
  var gdMethName = meth.toGodotStringName()

  gdInterfacePtr.classdb_get_method_bind(addr gdClassName, addr gdMethName, hash)

proc upRef[T](self: T): bool =
  let mb {.global.} = getClassMethodBindPtr("RefCounted", "reference", 2240911060)

  gdInterfacePtr.object_method_bind_ptrcall(
    mb,
    self.opaque,
    nil,
    addr result)

proc downRef[T](self: T): bool =
  let mb {.global.} = getClassMethodBindPtr("RefCounted", "unreference", 2240911060)

  gdInterfacePtr.object_method_bind_ptrcall(
    mb,
    self.opaque,
    nil,
    addr result)


proc `=destroy`*[T](r: var Ref[T]) =
  if r.reference == nil:
    return

  if r[].downRef():
    gdInterfacePtr.object_destroy(r.reference.opaque)

    r.reference = nil

proc `=sink`*[T](dest: var Ref[T]; source: Ref[T]) =
  `=destroy`(dest)

  dest.wasMoved()
  dest.reference = source.reference

proc `=copy`*[T](dest: var Ref[T]; source: Ref[T]) =
  if dest.reference == source.reference:
    return

  discard source[].upRef()

  `=destroy`(dest)
  dest.wasMoved()
  dest.reference = source.reference

proc newRefShallow*[T](reference: T): Ref[T] =
  ## Create a shallow reference to T. That is, a reference that doesn't
  ## count its own construction. We use this in one place: where Godot
  ## returns us a refcounted object from a return value, in which case
  ## the first reference is implied and this Ref[] will be the initial
  ## owner.
  assert T is ptr

  Ref[T](reference: reference)

proc newRef*[T](reference: T): Ref[T] =
  ## Create a reference to T, incrementing the reference count upon doing so.
  result = newRefShallow(reference)
  discard result[].upRef()

proc castRef*[T, U](r: sink Ref[T]; _: typedesc[U]): Ref[U] =
  ## Casts a Ref[T] to a Ref[U], raising an exception in case the transition
  ## is not allowed.

  # TBD: Cache these, since they never change for all possible U.
  var clsName = U.gdClassName()
  var clsTag = gdInterfacePtr.classdb_get_class_tag(clsName)

  let castedPtr = gdInterfacePtr.object_cast_to(r.reference.opaque, clsTag)

  if castedPtr.isNil():
    raise newException(ValueError, "Cannot cast object to type " & $T & " to " & $U)

  # N.B. we don't make use of castedPtr for now, since it's the same as the original.
  newRef(cast[U](r.reference))

proc `[]`*[T](r: Ref[T]): lent T =
  ## Return a lent reference to the contained value.
  r.reference

converter toObject*[T](x: sink Ref[T]): Object =
  x[]

# Owned[T] implementation

proc makeOwned*[T](reference: T): Owned[T] =
  assert T is ptr

  Owned[T](reference: reference)

proc `=destroy`*[T](r: var Owned[T]) =
  if r.reference == nil:
    return

  gdInterfacePtr.object_destroy(r.reference.opaque)
  r.reference = nil

proc `=sink`*[T](dest: var Owned[T]; source: Owned[T]) =
  `=destroy`(dest)

  dest.wasMoved()
  dest.reference = source.reference

proc `=copy`*[T](dest: var Owned[T]; source: Owned[T]) {.error.}

proc `[]`*[T: ptr](r: Owned[T]): lent T = r.reference