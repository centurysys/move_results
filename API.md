# move_results API Guide

This guide describes the public API of `move_results`.

## Core idea

`MoveResult` and `MoveOption` are **take-only** containers.

They are not general-purpose read-only containers. They are intended for
ownership transfer. A value can be extracted once. After extraction, the
container is consumed and further access raises `MoveResultDefect`.

There is intentionally no `get()` API.

## Types

```nim
type
  MoveResult[T, E]
  MoveOption[T]
  MoveOpt[T] = MoveOption[T]
  MoveResultDefect = object of Defect
```

### `MoveResult[T, E]`

Represents either:

- `Ok(T)`: a success value
- `Err(E)`: an error value
- consumed state after `take()` or `takeError()`

The success and error fields are private.

### `MoveOption[T]`

Represents either:

- `Some(T)`: a value
- `None`: no value
- consumed state after `take()`

The value field is private.

## Constructors

### `okMove`

```nim
return okMove(value)
return okMove(MoveResult[T, E], value)
```

Creates an `Ok` result by moving `value` into the container.

`okMove` uses `ensureMove(value)` internally. If the expression would require an
implicit copy, compilation fails.

The short form uses the enclosing proc's `result` type:

```nim
proc loadFrame(): MoveResult[Frame, ErrorCode] =
  var frame = makeFrame()

  return okMove(frame)
```

The explicit form is useful outside a proc return context:

```nim
var r = okMove(MoveResult[Frame, ErrorCode], frame)
```

### `errMove`

```nim
return errMove(error)
return errMove(MoveResult[T, E], error)
```

Creates an `Err` result.

Error values are usually small enums or codes, so `errMove` accepts immutable
literals such as `ErrorCode.Failed`. When the error expression can be moved,
`errMove` uses `ensureMove`; otherwise it falls back to normal assignment.

### `someMove`

```nim
return someMove(value)
```

Creates a `MoveOption[T]` by moving `value` into it.

`someMove` uses `ensureMove(value)` internally. If the expression would require
an implicit copy, compilation fails.

### `noneMove`

```nim
return noneMove(T)
```

Creates an empty `MoveOption[T]`.

## State queries

### `isOk`

```nim
if r.isOk:
  ...
```

Returns `true` if the result is `Ok`. Returns `false` if it is `Err`.

Raises `MoveResultDefect` if the result was already consumed.

### `isErr`

```nim
if r.isErr:
  ...
```

Returns `true` if the result is `Err`. Returns `false` if it is `Ok`.

Raises `MoveResultDefect` if the result was already consumed.

### `isSome`

```nim
if opt.isSome:
  ...
```

Returns `true` if the option is `Some`. Returns `false` if it is `None`.

Raises `MoveResultDefect` if the option was already consumed.

### `isNone`

```nim
if opt.isNone:
  ...
```

Returns `true` if the option is `None`. Returns `false` if it is `Some`.

Raises `MoveResultDefect` if the option was already consumed.

## Extracting values

### `take`

```nim
var value = r.take()
var value = opt.take()
```

Moves the success value out of a `MoveResult` or the value out of a
`MoveOption`.

This can be done only once.

```nim
var r = loadFrame()
var frame = r.take()

discard r.isOk    # MoveResultDefect
discard r.take()  # MoveResultDefect
```

`take()` uses explicit field move-out. Nim 2.2 rejects
`ensureMove(self.value)` for object fields, while `move self.value` is the
field move-out operation used and tested by this package.

### `takeError`

```nim
var err = r.takeError()
```

Moves the error value out of a `MoveResult`.

This can be done only once. After `takeError()`, the result is consumed.

### `error`

```nim
echo r.error
```

Borrows the error value as `lent E`.

This is useful for inspecting small error values. Use `takeError()` if the error
itself is an ownership object.

## Propagation with `?`

### `MoveResult`

```nim
proc readFrame(): MoveResult[Frame, ErrorCode] =
  ...

proc processFrame(): MoveResult[Frame, ErrorCode] =
  var frame = ?readFrame()

  # frame was moved out of readFrame()'s Ok value

  return okMove(frame)
```

If the expression is `Ok`, `?` takes the success value.

If the expression is `Err`, `?` takes the error value and returns it from the
enclosing proc.

### `MoveOption`

```nim
proc tryReadPacket(): MoveOption[Packet] =
  ...

proc readAndProcess(): MoveOption[Packet] =
  var packet = ?tryReadPacket()

  # packet was moved out of Some

  return someMove(packet)
```

If the expression is `Some`, `?` takes the value.

If the expression is `None`, `?` returns `None` from the enclosing proc.

## Copy prevention

`MoveResult` and `MoveOption` cannot be copied.

```nim
var a = loadFrame()
var b = a  # compile error
```

Use `move`, `take()`, or `?` instead.

## Comparison with std/options and results

Use standard `Option` or conventional `Result` when you need a normal value
container, borrowed access, repeated inspection, or lightweight values.

Use `MoveResult` / `MoveOption` when success values are ownership objects and the
normal operation is to consume the container exactly once.

A useful rule of thumb:

- `get` means borrow/read
- `take` means move out and consume

## Supported memory managers

`move_results` targets ARC/ORC.

The no-copy move-out behavior is tested under ARC/ORC. `refc` is not a supported
target for pointer-stability guarantees.
