# move_results

Take-only `Result` and `Option` types for ownership-safe move-out semantics in Nim.

`move_results` provides small single-use containers for APIs that return large
value objects such as buffers, frames, packets, or pool items. Unlike
`std/options.get` or conventional `Result.value` APIs, successful values are not
"read" from the container. They are **taken** from it.

After a value or error is extracted, the container becomes consumed.

## Why?

Nim's standard `Option[T].get` returns a borrowed `lent T`. That is the right
choice for many APIs, but when the caller writes an owned value such as:

```nim
let value = opt.get
```

a large value object containing `seq` or `string` storage may be copied when the
borrowed value is converted into an owned value.

`ensureMove(opt.get)` does not turn this into a move. In Nim 2.2, it is rejected
because the expression would introduce an implicit copy. This is a useful safety
check, and it also makes the distinction clear: `Option.get` is a borrow-style
API, not a take/move-out API.

`move_results` is for the other case: APIs where the caller wants to move the
successful value out and never use the container again.

## Features

- `MoveResult[T, E]`: single-use value-or-error container
- `MoveOption[T]`: single-use optional value container
- `take()` for moving a value out
- `takeError()` for moving an error out
- `?` propagation for both `MoveResult` and `MoveOption`
- no `get()` API
- private payload fields
- copy prevention
- source values passed to `okMove` / `someMove` are rejected if reused afterwards
- use-after-take detection via `MoveResultDefect`
- `ensureMove()` at construction time to reject accidental implicit copies

## Requirements

`move_results` targets Nim 2.x with ARC/ORC.

The API may compile under `refc`, but no-copy move-out semantics are intended and
tested for ARC/ORC only.

## Installation

```sh
nimble install move_results
```

Or place `move_results.nim` directly in your project and import it:

```nim
import move_results
```

## Quick example

```nim
import move_results

type
  ErrorCode = enum
    Invalid
    Full

  Frame = object
    data: seq[byte]

proc makeFrame(): MoveResult[Frame, ErrorCode] =
  var frame = Frame(data: newSeq[byte](1024 * 1024))

  return okMove(frame)

proc processFrame(): MoveResult[Frame, ErrorCode] =
  var frame = ?makeFrame()

  frame.data[0] = 1

  return okMove(frame)

var r = processFrame()

if r.isOk:
  var frame = r.take()
  echo frame.data.len
else:
  echo r.error
```

## MoveOption example

```nim
import move_results

type
  Packet = object
    payload: seq[byte]

proc tryReadPacket(): MoveOption[Packet] =
  var packet = Packet(payload: newSeq[byte](4096))

  return someMove(packet)

proc readAndUse(): MoveOption[Packet] =
  var packet = ?tryReadPacket()

  packet.payload[0] = 42

  return someMove(packet)
```

## Source values are consumed at construction

`okMove` and `someMove` use `ensureMove()` when storing a value into
`MoveResult` or `MoveOption`.

This means the source value must be the last use. Code that tries to read the
source value after passing it to `okMove` or `someMove` is rejected at compile
time.

```nim
var frame = makeFrame()

let r = okMove(MoveResult[Frame, ErrorCode], frame)

discard frame.data.len  # compile error
```

This helps catch accidental source reuse when transferring ownership into a
`move_results` container.

## Single-use behavior

`MoveResult` and `MoveOption` are intentionally single-use.

```nim
var r = makeFrame()
var frame = r.take()

discard r.isOk    # raises MoveResultDefect
discard r.take()  # raises MoveResultDefect
```

The same rule applies to `MoveOption`.

## Implementation note

`okMove` and `someMove` use `ensureMove(valueExpr)` to reject accidental implicit
copies at construction time.

`take()` and `takeError()` use Nim's explicit field move-out operation
(`move self.value` / `move self.error`). Nim 2.2 rejects
`ensureMove(self.value)` for object fields, while explicit field move-out passes
the ARC/ORC pointer-stability tests used by this package.

## When to use this

Use `move_results` when:

- successful values are large value objects
- values own buffers or other resources
- the caller normally consumes the result immediately
- you want Rust-like `Result`/`Option` consumption behavior in Nim

Do not use it when:

- you want to inspect the same result multiple times
- you need borrowed access to the success value
- the value is small and conventional `Option`/`Result` is simpler

## Testing

```sh
nimble test
```

The test suite covers ARC/ORC debug and release builds, including compile-fail
checks that verify source values cannot be read after being passed to `okMove` or
`someMove`.
