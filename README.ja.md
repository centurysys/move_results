# move_results

Nim 向けの、`take()` 専用 `Result` / `Option` 型です。

`move_results` は、buffer、frame、packet、pool item のような大きな value object を返す API のための小さな single-use container です。`std/options.get` や一般的な `Result.value` のように「中身を読む」のではなく、成功値を **取り出す** ことを目的にしています。

値または error を取り出した後、その container は consumed 状態になります。

## なぜ必要か

Nim 標準の `Option[T].get` は `lent T` を返します。これは多くの用途では正しい設計ですが、呼び出し側で次のように owned value として受けると、

```nim
let value = opt.get
```

`seq` や `string` を持つ大きな value object では、borrowed value から owned value へ変換される段階で backing storage がコピーされることがあります。

`move_results` は、その逆の用途向けです。つまり、「成功値を move out して、その container は二度と使わない」API のための型です。

## 特長

- `MoveResult[T, E]`: single-use な value-or-error container
- `MoveOption[T]`: single-use な optional value container
- `take()` による成功値の move out
- `takeError()` による error の move out
- `MoveResult` / `MoveOption` 両方に対応する `?` propagation
- `get()` API は提供しない
- payload field は private
- copy 禁止
- take 後の再アクセスは `MoveResultDefect`

## 要件

`move_results` は Nim 2.x の ARC/ORC を対象にしています。

`refc` でもコンパイルできる可能性はありますが、no-copy move-out semantics は ARC/ORC を対象としてテストします。

## インストール

```sh
nimble install move_results
```

または、`move_results.nim` をプロジェクトに直接置いて import します。

```nim
import move_results
```

## 簡単な例

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

## MoveOption の例

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

## single-use の挙動

`MoveResult` と `MoveOption` は意図的に single-use です。

```nim
var r = makeFrame()
var frame = r.take()

discard r.isOk    # MoveResultDefect
discard r.take()  # MoveResultDefect
```

`MoveOption` も同様です。

## 使うべき場面

`move_results` が向いている場面:

- 成功値が大きな value object
- 値が buffer や resource を所有している
- 呼び出し側が結果をすぐ consume する
- Rust の `Result` / `Option` のような consume 挙動を Nim で使いたい

向いていない場面:

- 同じ result を何度も参照したい
- 成功値を borrow して読みたい
- 値が軽量で、通常の `Option` / `Result` のほうが単純な場合

## テスト

```sh
nimble test
```

テスト対象は ARC/ORC の debug / release build を想定しています。
