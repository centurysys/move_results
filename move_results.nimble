# Package

version       = "0.1.0"
author        = "Takeyoshi Kikuchi"
description   = "Take-only Result and Option types for ownership-safe move-out semantics in Nim."
license       = "MIT"
srcDir        = "src"
skipDirs      = @["tests"]


# Dependencies

requires "nim >= 2.2.10"

proc test(env, path: string) =
  var lang = "c"

  if existsEnv"TEST_LANG":
    lang = getEnv"TEST_LANG"

  exec "nim " & lang & " " & env & " -r " & path

task test, "Runs the test suite":
  for f in ["test_move_results.nim"]:
    test "--mm:orc --threads:on -d:release", "tests/" & f
    test "--mm:arc --threads:on -d:release", "tests/" & f
