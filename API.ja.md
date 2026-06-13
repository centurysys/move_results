# move_results API Guide 日本語版

この文書は `move_results` の公開 API を説明します。

## 基本方針

`MoveResult` と `MoveOption` は **take-only** container です。

これは汎用の読み取り用 container ではありません。目的は ownership transfer です。値は1回だけ取り出せます。取り出した後、その container は consumed 状態になり、以後のアクセスは `MoveResultDefect` になります。

`get()` API は意図的に提供しません。

## 型

```nim
type
  MoveResult[T, E]
  MoveOption[T]
  MoveOpt[T] = MoveOption[T]
  MoveResultDefect = object of Defect
```

### `MoveResult[T, E]`

次のどれかを表します。

- `Ok(T)`: 成功値
- `Err(E)`: error 値
- `take()` または `takeError()` 後の consumed 状態

成功値と error field は private です。

### `MoveOption[T]`

次のどれかを表します。

- `Some(T)`: 値あり
- `None`: 値なし
- `take()` 後の consumed 状態

value field は private です。

## constructor

### `okMove`

```nim
return okMove(value)
return okMove(MoveResult[T, E], value)
```

`value` を move して `Ok` result を作ります。

短い形式では、外側の proc の `result` 型を使います。

```nim
proc loadFrame(): MoveResult[Frame, ErrorCode] =
  var frame = makeFrame()

  return okMove(frame)
```

型を明示する形式は、proc の return context 以外で便利です。

```nim
var r = okMove(MoveResult[Frame, ErrorCode], frame)
```

### `errMove`

```nim
return errMove(error)
return errMove(MoveResult[T, E], error)
```

`Err` result を作ります。

error は `ErrorCode` のような軽量 enum / code であることが多いため、`errMove` は error expression に `move` を強制しません。そのため `ErrorCode.Failed` のような enum literal もそのまま渡せます。

### `someMove`

```nim
return someMove(value)
```

`value` を move して `MoveOption[T]` を作ります。

### `noneMove`

```nim
return noneMove(T)
```

空の `MoveOption[T]` を作ります。

## 状態確認

### `isOk`

```nim
if r.isOk:
  ...
```

result が `Ok` なら `true`、`Err` なら `false` を返します。

すでに consumed 状態なら `MoveResultDefect` になります。

### `isErr`

```nim
if r.isErr:
  ...
```

result が `Err` なら `true`、`Ok` なら `false` を返します。

すでに consumed 状態なら `MoveResultDefect` になります。

### `isSome`

```nim
if opt.isSome:
  ...
```

option が `Some` なら `true`、`None` なら `false` を返します。

すでに consumed 状態なら `MoveResultDefect` になります。

### `isNone`

```nim
if opt.isNone:
  ...
```

option が `None` なら `true`、`Some` なら `false` を返します。

すでに consumed 状態なら `MoveResultDefect` になります。

## 値の取り出し

### `take`

```nim
var value = r.take()
var value = opt.take()
```

`MoveResult` から成功値を、または `MoveOption` から値を move out します。

これは1回だけ実行できます。

```nim
var r = loadFrame()
var frame = r.take()

discard r.isOk    # MoveResultDefect
discard r.take()  # MoveResultDefect
```

### `takeError`

```nim
var err = r.takeError()
```

`MoveResult` から error 値を move out します。

これも1回だけ実行できます。`takeError()` 後、result は consumed 状態になります。

### `error`

```nim
echo r.error
```

error 値を `lent E` として borrow します。

軽量な error 値を確認するための API です。error 自体が ownership object の場合は `takeError()` を使います。

## `?` propagation

### `MoveResult`

```nim
proc readFrame(): MoveResult[Frame, ErrorCode] =
  ...

proc processFrame(): MoveResult[Frame, ErrorCode] =
  var frame = ?readFrame()

  # frame は readFrame() の Ok 値から move out された値

  return okMove(frame)
```

式が `Ok` なら、`?` は成功値を `take()` します。

式が `Err` なら、`?` は error 値を `takeError()` して、外側の proc からその error を返します。

### `MoveOption`

```nim
proc tryReadPacket(): MoveOption[Packet] =
  ...

proc readAndProcess(): MoveOption[Packet] =
  var packet = ?tryReadPacket()

  # packet は Some から move out された値

  return someMove(packet)
```

式が `Some` なら、`?` は値を `take()` します。

式が `None` なら、`?` は外側の proc から `None` を返します。

## copy 禁止

`MoveResult` と `MoveOption` は copy できません。

```nim
var a = loadFrame()
var b = a  # compile error
```

代わりに `move`、`take()`、または `?` を使います。

## std/options や results との使い分け

通常の value container、borrow access、繰り返し参照、軽量値には標準 `Option` や一般的な `Result` が向いています。

成功値が ownership object であり、container を1回だけ consume するのが通常の操作である場合は、`MoveResult` / `MoveOption` が向いています。

## 対象 memory manager

`move_results` は ARC/ORC を対象にしています。

no-copy move-out の挙動は ARC/ORC でテストします。`refc` は pointer stability guarantee の対象外です。
