/**
  Test runner. Evaluating `tests` yields the number of test cases if all pass, otherwise
  it throws a single error listing every failing case.

  Run with `nix eval .#tests` or `nix flake check`.

  # Test case files
  Each file in `testFiles` is a function returning a list of test cases:

  ```nix
  { lib, netLib, throws, ... }: with builtins; with lib; with netLib; [
    {
      description = "What is tested";
      expression = ip4.check "1.2.3.4";
      expected = true;
    }
  ]
  ```

  - `lib` : nixpkgs lib, `netLib` : this library (also `netLib.types`).
  - `throws x` : true if deeply evaluating `x` throws (via `builtins.tryEval`), e.g.
    `expression = throws (ip4.decompose "foo"); expected = true;`. Only `throw` and
    `assert` are caught, not type errors.
  - `expression == expected` passes. If `expected` is an attribute set, only its
    attributes are compared and attributes starting with "_" (e.g. `_meta`) are ignored.
  - An expression that throws is reported as a failure instead of aborting the run.
*/
{ nixpkgs ? null
, lib ? nixpkgs.lib
, netLib ? import ./lib.nix { inherit lib; }
, ...
}:
with builtins; with lib;
let
  testFiles = [
    ./tests/core.nix
    ./tests/types.nix
    ./tests/api.nix
  ];

  throws = x: !(tryEval (deepSeq x x)).success;

  testCases = concatMap (file: import file { inherit lib netLib throws; }) testFiles;

  # Returns null if the test case passes, otherwise a message describing the failure.
  runTestCase = index: testCase:
    let
      inherit (testCase) description;
      evaluated = tryEval (deepSeq testCase.expression testCase.expression);
      expression = evaluated.value;
      expected = testCase.expected;

      allEqual = list: all (x: x == head list) list;
      bothSets = typeOf expression == "set" && typeOf expected == "set";
      onlyDifference = attrsets.filterAttrs
        (k: v: (!(allEqual v) || length v != 2) && (head (strings.stringToCharacters k) != "_"))
        (attrsets.zipAttrs [ expression expected ]);
      differenceSet = attrNames onlyDifference;

      showValue = v: let r = tryEval (toJSON v); in if r.success then r.value else "<${typeOf v}>";

      mismatchString =
        if bothSets then
          "Difference in attributes: ${showValue onlyDifference}."
        else
          "Expected ${showValue expected}, got ${showValue expression}.";

      prefix = "Test ${toString (index + 1)} failed: '${description}'.";
    in
    if !evaluated.success then
      "${prefix} The expression threw an error."
    else if expression == expected || (bothSets && length differenceSet == 0) then
      null
    else
      "${prefix} ${mismatchString}";

  failures = filter (x: x != null) (imap0 runTestCase testCases);
in
{
  tests =
    if failures == [ ] then
      length testCases
    else
      throw "${toString (length failures)} of ${toString (length testCases)} tests failed:\n${concatStringsSep "\n" failures}";
}
