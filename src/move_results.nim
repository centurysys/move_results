# ------------------------------------------------------------------------------
# move_results
#
# Take-only Result and Option types for ownership-safe move-out semantics.
#
# MoveResult and MoveOption are intended for large value objects such as buffers,
# frames, and pool items.  They do not provide get().  Successful values are
# extracted with take() or ?, after which the container becomes consumed.
# ------------------------------------------------------------------------------

type
  MoveResultDefect* = object of Defect
    ## Raised when a MoveResult / MoveOption is used after it was consumed, or
    ## when a value/error is taken from the wrong state.

  MoveResultState = enum
    mrsTaken
    mrsOk
    mrsErr

  MoveOptionState = enum
    mosNone
    mosSome
    mosTaken

  MoveResult*[T, E] = object
    ## Single-use value-or-error container.
    ##
    ## The success value can only be extracted once, using take() or ?.
    ## The fields are intentionally private.
    state: MoveResultState
    value: T
    error: E

  MoveOption*[T] = object
    ## Single-use optional value container.
    ##
    ## The value can only be extracted once, using take() or ?.
    ## The fields are intentionally private.
    state: MoveOptionState
    value: T

  MoveOpt*[T] = MoveOption[T]

# ------------------------------------------------------------------------------
# Copy prevention:
# ------------------------------------------------------------------------------

proc `=copy`*[T, E](dest: var MoveResult[T, E]; src: MoveResult[T, E]) {.error:
    "MoveResult cannot be copied; use move, take(), or ? instead".}

proc `=copy`*[T](dest: var MoveOption[T]; src: MoveOption[T]) {.error:
    "MoveOption cannot be copied; use move, take(), or ? instead".}

# ------------------------------------------------------------------------------
# Defect helpers:
# ------------------------------------------------------------------------------

proc raiseMoveResultDefect(msg: string) {.noinline, noreturn.} =
  raise newException(MoveResultDefect, msg)

# ------------------------------------------------------------------------------
# MoveResult constructors:
# ------------------------------------------------------------------------------

template okMove*(R: typedesc, valueExpr: untyped): untyped =
  ## Creates an Ok MoveResult for the explicitly supplied result type.
  ##
  ## Example:
  ##   return okMove(MoveResult[Frame, ErrorCode], frame)
  block:
    var ret: R
    ret.state = mrsOk
    ret.value = move valueExpr
    ret

template errMove*(R: typedesc, errorExpr: untyped): untyped =
  ## Creates an Err MoveResult for the explicitly supplied result type.
  ##
  ## Error values are usually small enums/codes.  This constructor does not force
  ## move because literals such as ErrorCode.Failed are immutable.
  block:
    var ret: R
    ret.state = mrsErr
    ret.error = errorExpr
    ret

template okMove*(valueExpr: untyped): untyped =
  ## Creates an Ok MoveResult using the enclosing proc's result type.
  ##
  ## Example:
  ##   proc f(): MoveResult[Frame, ErrorCode] =
  ##     var frame = makeFrame()
  ##     return okMove(frame)
  okMove(typeof(result), valueExpr)

template errMove*(errorExpr: untyped): untyped =
  ## Creates an Err MoveResult using the enclosing proc's result type.
  ##
  ## Example:
  ##   return errMove(ErrorCode.Failed)
  errMove(typeof(result), errorExpr)

# ------------------------------------------------------------------------------
# MoveOption constructors:
# ------------------------------------------------------------------------------

template someMove*(valueExpr: untyped): untyped =
  ## Creates a MoveOption containing valueExpr.
  block:
    var ret: MoveOption[typeof(valueExpr)]
    ret.state = mosSome
    ret.value = move valueExpr
    ret

template noneMove*(T: typedesc): MoveOption[T] =
  ## Creates an empty MoveOption[T].
  block:
    var ret: MoveOption[T]
    ret.state = mosNone
    ret

# ------------------------------------------------------------------------------
# MoveResult state:
# ------------------------------------------------------------------------------

proc isOk*[T, E](self: MoveResult[T, E]): bool {.inline.} =
  ## Returns true for Ok and false for Err.
  ##
  ## Raises MoveResultDefect if the result was already consumed.
  case self.state
  of mrsOk:
    return true
  of mrsErr:
    return false
  of mrsTaken:
    raiseMoveResultDefect("MoveResult was already taken")

proc isErr*[T, E](self: MoveResult[T, E]): bool {.inline.} =
  ## Returns true for Err and false for Ok.
  ##
  ## Raises MoveResultDefect if the result was already consumed.
  case self.state
  of mrsOk:
    return false
  of mrsErr:
    return true
  of mrsTaken:
    raiseMoveResultDefect("MoveResult was already taken")

# ------------------------------------------------------------------------------
# MoveOption state:
# ------------------------------------------------------------------------------

proc isSome*[T](self: MoveOption[T]): bool {.inline.} =
  ## Returns true for Some and false for None.
  ##
  ## Raises MoveResultDefect if the option was already consumed.
  case self.state
  of mosSome:
    return true
  of mosNone:
    return false
  of mosTaken:
    raiseMoveResultDefect("MoveOption was already taken")

proc isNone*[T](self: MoveOption[T]): bool {.inline.} =
  ## Returns true for None and false for Some.
  ##
  ## Raises MoveResultDefect if the option was already consumed.
  case self.state
  of mosSome:
    return false
  of mosNone:
    return true
  of mosTaken:
    raiseMoveResultDefect("MoveOption was already taken")

# ------------------------------------------------------------------------------
# MoveResult take:
# ------------------------------------------------------------------------------

proc take*[T, E](self: var MoveResult[T, E]): T =
  ## Moves the Ok value out of self.
  ##
  ## This can be done only once.  After take(), self enters the consumed state and
  ## must not be queried again.
  case self.state
  of mrsOk:
    result = move self.value
    self.state = mrsTaken
  of mrsErr:
    raiseMoveResultDefect("cannot take value from error MoveResult")
  of mrsTaken:
    raiseMoveResultDefect("cannot take value from already taken MoveResult")

proc takeError*[T, E](self: var MoveResult[T, E]): E =
  ## Moves the Err value out of self.
  ##
  ## This can be done only once.  After takeError(), self enters the consumed
  ## state and must not be queried again.
  case self.state
  of mrsOk:
    raiseMoveResultDefect("cannot take error from ok MoveResult")
  of mrsErr:
    result = move self.error
    self.state = mrsTaken
  of mrsTaken:
    raiseMoveResultDefect("cannot take error from already taken MoveResult")

proc error*[T, E](self: MoveResult[T, E]): lent E {.inline.} =
  ## Borrows the Err value.
  ##
  ## This is intended for inspecting small error values.  Use takeError() when the
  ## error itself is an ownership object.
  case self.state
  of mrsOk:
    raiseMoveResultDefect("cannot borrow error from ok MoveResult")
  of mrsErr:
    return self.error
  of mrsTaken:
    raiseMoveResultDefect("cannot borrow error from already taken MoveResult")

# ------------------------------------------------------------------------------
# MoveOption take:
# ------------------------------------------------------------------------------

proc take*[T](self: var MoveOption[T]): T =
  ## Moves the Some value out of self.
  ##
  ## This can be done only once.  After take(), self enters the consumed state and
  ## must not be queried again.
  case self.state
  of mosSome:
    result = move self.value
    self.state = mosTaken
  of mosNone:
    raiseMoveResultDefect("cannot take value from none MoveOption")
  of mosTaken:
    raiseMoveResultDefect("cannot take value from already taken MoveOption")

# ------------------------------------------------------------------------------
# Question-mark propagation:
# ------------------------------------------------------------------------------

template `?`*[T, E](expr: MoveResult[T, E]): untyped =
  ## Unwraps an Ok value or returns Err from the enclosing proc.
  ##
  ## The source MoveResult is consumed.  The Ok value is extracted with take().
  ## The Err value is propagated with takeError().
  block:
    var ret = expr

    if ret.isErr:
      return errMove(ret.takeError())

    ret.take()

template `?`*[T](expr: MoveOption[T]): untyped =
  ## Unwraps a Some value or returns None from the enclosing proc.
  ##
  ## The source MoveOption is consumed.  The Some value is extracted with take().
  block:
    var ret = expr

    if ret.isNone:
      return noneMove(T)

    ret.take()
