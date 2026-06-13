import std/strformat
import ../src/move_results

type
  ErrorCode = enum
    ecInvalid
    ecFailed

  Buf = object
    data: seq[byte]

var lastProducerPtr: uint

template dataPtr(x: untyped): uint =
  (if x.data.len == 0:
     0'u
   else:
     cast[uint](unsafeAddr x.data[0]))

proc fail(msg: string) =
  echo "ERROR: " & msg
  quit 1

template expectDefect(name: string, body: untyped) =
  block:
    var raised = false

    try:
      body
    except MoveResultDefect:
      raised = true

    if not raised:
      fail(name & ": MoveResultDefect was not raised")

proc makeBuf(tag: byte): Buf =
  result.data = newSeq[byte](1024 * 1024)
  result.data[0] = tag
  result.data[^1] = tag

proc checkStable(name: string, before: uint, after: uint) =
  if before != after:
    echo name
    echo &"  before = {before}"
    echo &"  after  = {after}"
    echo &"  delta  = {after.int64 - before.int64}"
    fail(name & ": backing pointer changed")

# ------------------------------------------------------------------------------
# Producers:
# ------------------------------------------------------------------------------

proc produceOk(tag: byte): MoveResult[Buf, ErrorCode] =
  var b = makeBuf(tag)
  lastProducerPtr = dataPtr(b)

  return okMove(b)

proc produceErr(): MoveResult[Buf, ErrorCode] =
  return errMove(ErrorCode.ecFailed)

proc produceOkExplicit(tag: byte): MoveResult[Buf, ErrorCode] =
  var b = makeBuf(tag)
  lastProducerPtr = dataPtr(b)

  return okMove(MoveResult[Buf, ErrorCode], b)

proc produceErrExplicit(): MoveResult[Buf, ErrorCode] =
  return errMove(MoveResult[Buf, ErrorCode], ErrorCode.ecFailed)

proc produceSome(tag: byte): MoveOption[Buf] =
  var b = makeBuf(tag)
  lastProducerPtr = dataPtr(b)

  return someMove(b)

proc produceNone(): MoveOption[Buf] =
  return noneMove(Buf)

proc passOk(): MoveResult[Buf, ErrorCode] =
  var b = ?produceOk(10)

  return okMove(b)

proc passErr(): MoveResult[Buf, ErrorCode] =
  var b = ?produceErr()

  return okMove(b)

proc passSome(): MoveOption[Buf] =
  var b = ?produceSome(20)

  return someMove(b)

proc passNone(): MoveOption[Buf] =
  var b = ?produceNone()

  return someMove(b)

# ------------------------------------------------------------------------------
# MoveResult tests:
# ------------------------------------------------------------------------------

proc testMoveResultOk() =
  var r = produceOk(1)

  doAssert r.isOk
  doAssert not r.isErr

  var b = r.take()
  doAssert b.data[0] == 1
  checkStable("MoveResult ok take", lastProducerPtr, dataPtr(b))

proc testMoveResultErr() =
  var r = produceErr()

  doAssert r.isErr
  doAssert not r.isOk
  doAssert r.error == ErrorCode.ecFailed

  let e = r.takeError()
  doAssert e == ErrorCode.ecFailed

proc testMoveResultExplicitConstructors() =
  var okR = produceOkExplicit(2)

  doAssert okR.isOk

  var b = okR.take()
  doAssert b.data[0] == 2
  checkStable("MoveResult explicit okMove take", lastProducerPtr, dataPtr(b))

  var errR = produceErrExplicit()
  doAssert errR.isErr
  doAssert errR.takeError() == ErrorCode.ecFailed

proc testMoveResultQuestionMarkOk() =
  var r = passOk()

  doAssert r.isOk

  var b = r.take()
  doAssert b.data[0] == 10
  checkStable("MoveResult ? ok take", lastProducerPtr, dataPtr(b))

proc testMoveResultQuestionMarkErr() =
  var r = passErr()

  doAssert r.isErr
  doAssert r.takeError() == ErrorCode.ecFailed

proc testMoveResultMisuse() =
  block:
    var r = produceOk(3)
    discard r.take()

    expectDefect("MoveResult take twice"):
      discard r.take()

  block:
    var r = produceOk(4)
    discard r.take()

    expectDefect("MoveResult isOk after take"):
      discard r.isOk

  block:
    var r = produceErr()
    discard r.takeError()

    expectDefect("MoveResult isErr after takeError"):
      discard r.isErr

  block:
    var r = produceErr()

    expectDefect("MoveResult take from err"):
      discard r.take()

  block:
    var r = produceOk(5)

    expectDefect("MoveResult takeError from ok"):
      discard r.takeError()

  block:
    var r = produceErr()
    discard r.takeError()

    expectDefect("MoveResult error after takeError"):
      discard r.error

# ------------------------------------------------------------------------------
# MoveOption tests:
# ------------------------------------------------------------------------------

proc testMoveOptionSome() =
  var o = produceSome(6)

  doAssert o.isSome
  doAssert not o.isNone

  var b = o.take()
  doAssert b.data[0] == 6
  checkStable("MoveOption some take", lastProducerPtr, dataPtr(b))

proc testMoveOptionNone() =
  var o = produceNone()

  doAssert o.isNone
  doAssert not o.isSome

proc testMoveOptionQuestionMarkSome() =
  var o = passSome()

  doAssert o.isSome

  var b = o.take()
  doAssert b.data[0] == 20
  checkStable("MoveOption ? some take", lastProducerPtr, dataPtr(b))

proc testMoveOptionQuestionMarkNone() =
  var o = passNone()

  doAssert o.isNone

proc testMoveOptionMisuse() =
  block:
    var o = produceSome(7)
    discard o.take()

    expectDefect("MoveOption take twice"):
      discard o.take()

  block:
    var o = produceSome(8)
    discard o.take()

    expectDefect("MoveOption isSome after take"):
      discard o.isSome

  block:
    var o = produceNone()

    expectDefect("MoveOption take from none"):
      discard o.take()

# ------------------------------------------------------------------------------
# Main:
# ------------------------------------------------------------------------------

when isMainModule:
  testMoveResultOk()
  testMoveResultErr()
  testMoveResultExplicitConstructors()
  testMoveResultQuestionMarkOk()
  testMoveResultQuestionMarkErr()
  testMoveResultMisuse()

  testMoveOptionSome()
  testMoveOptionNone()
  testMoveOptionQuestionMarkSome()
  testMoveOptionQuestionMarkNone()
  testMoveOptionMisuse()

  echo "test_move_results: OK"
