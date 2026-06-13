import ../src/move_results

type
  Buf = object
    data: seq[byte]

proc makeBuf(): Buf =
  result.data = newSeq[byte](1024)

proc testSomeMoveUseAfterMove() =
  var b = makeBuf()

  let opt = someMove(b)

  # This must not compile.
  #
  # someMove() uses ensureMove(b), so b must be the last use.
  # Reading b after it was moved into MoveOption would require an implicit copy
  # or a use-after-move style access.
  discard b.data.len

  discard opt

proc testOkMoveUseAfterMove() =
  var b = makeBuf()

  let r = okMove(MoveResult[Buf, string], b)

  # This must not compile for the same reason.
  discard b.data.len

  discard r

when isMainModule:
  testSomeMoveUseAfterMove()
  testOkMoveUseAfterMove()
