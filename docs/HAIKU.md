# Drafting snippets with a small model

Rakuglaze grows past what can be hand-reduced by letting a small model
(Haiku) draft snippets from pre-picked corpus lines, and letting the tooling
decide what is admitted. The model never writes into `glaze/`.

1. `rakupp tools/pick.raku --n=250 --out=tmp/haiku/batch-NN.tsv` picks the rows.
2. A Haiku session runs the prompt below on that batch and leaves a draft
   in `tmp/haiku/batch-NN.draft.glaze`.
3. `rakupp tools/accept.raku --batch=tmp/haiku/batch-NN.tsv --name=batch-NN tmp/haiku/batch-NN.draft.glaze`
   admits what passes into `glaze/haiku/batch-NN.glaze`, with expectations
   recorded by Rakudo, and writes the rest to `tmp/haiku/batch-NN.rejected.glaze`
   with a reason each.

The first batch (200 rows) gave 174 drafts and 133 admitted snippets.

---

## The prompt

Start the session in `/Users/ash/rakuglaze` with the model set to Haiku, and
paste this with `NN` replaced by the batch number:

```
Read /Users/ash/rakuglaze/docs/HAIKU.md, section "Instructions", and carry it out for batch NN.
```

## Instructions

You turn real lines of Raku code, taken from published modules, into small
standalone test snippets for Rakuglaze, a regression suite for Raku
implementations. Work in `/Users/ash/rakuglaze`.

**Input:** `tmp/haiku/batch-NN.tsv` — rows of `dist  version  file  line  license  code`,
tab-separated. **Output:** one file, `tmp/haiku/batch-NN.draft.glaze`. Write
nothing else, anywhere.

### One snippet per row

For each row write **one** snippet that runs the row's construct the way the
module wrote it — or skip the row. A snippet:

- is 3 to 12 lines of Raku that run alone: no `use` of a module, no files,
  network, `%*ENV`, `now`, `rand`, `sleep`, `exit`, `MAIN` or `unit`;
- **keeps the row's construct**: the same method, operator, trait, adverb or
  idiom. If the row is `make $<x>.made + $<y>.made`, the snippet must have a
  grammar whose action does `make … .made`; if the row uses `with`, the
  snippet uses `with`. Replace only the module's own names and data with tiny
  stand-ins (`my class`, `my grammar`, literal strings, small arrays) — always
  `my class`, never a bare `class`;
- **prints** what the construct produces with `say` or `put`: derived values,
  sorted when they come from a Hash or Set, the same on every run;
- may end by letting an exception escape when the row itself throws (`die`,
  `fail`, `.throw`).

Skip the row when it is pod or English text, a bare declaration with nothing
to run, native/C binding, I/O, or so tied to its module that a stand-in would
test something else. Skipping is always better than a snippet that tests the
wrong thing.

### Format

    === hk-NN-<short-kebab-id>
    from: <dist> <version> <file>:<line>
    license: <license>
    feature: <the construct: "method subst", "infix //", "trait is rw", …>
    --- code
    <the snippet>

Snippets are separated by a blank line. `from:` and `license:` are copied
**exactly** from the row. Every id starts with `hk-NN-` and is unique. **Never
write a `--- expect` block** — the tooling records it.

### Loop, about 25 rows at a time

1. Append the next snippets to the draft with your file-editing tool (not a
   shell heredoc: it mangles backslashes).
2. Check them:

       /Users/ash/raku++/build-arm64/rakupp tools/accept.raku --batch=tmp/haiku/batch-NN.tsv --dry tmp/haiku/batch-NN.draft.glaze

   It prints, for every snippet, what Rakudo prints, and a `PROBLEM:` line for
   every snippet that would be rejected. **Fix every PROBLEM** in your
   snippets, then run it again:
   - `its expectation is a compile error` — your Raku is wrong; fix it.
   - `drifted: keeps none of …` — your snippet lost the row's construct; put
     it back.
   - `prints nothing`, `Rakudo: crash/hang`, `output differs between two runs`
     — fix it or delete the snippet.
   - `a second snippet for the same row` — delete one.
3. Also read the printed output of each new snippet: if it is not what the
   construct should produce (an unexpected `!! X::…` line, `(Any)` where a
   value was meant), fix the code.

Run nothing else. Never edit anything but your draft, never run more than one
command at a time, never run anything in the background, never commit.

### Report

When every row is written or skipped and the last `--dry` run shows no
`PROBLEM:` line for snippets you mean to keep, report:

- rows written / skipped, with skip reasons grouped and counted
- the last line of the final `--dry` run
- anything in these instructions that was unclear
