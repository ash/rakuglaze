# Rakuglaze

Short Raku snippets taken from real ecosystem modules, run against a Raku
engine in seconds.

Roast says whether an implementation is Raku. Rakuglaze says whether the code
people actually publish still works after the engine changes. Every snippet
is a construct as a module author wrote it — a `new` over `bless`, a
`subset ... where any(...)`, a grammar rule with `*%%`, a `.classify` into
named captures — reduced until it runs alone, with no module installed and
nothing fetched.

## Running

The engine under test is the one that runs the script, as with Roast's
`tools/run-roast.raku`:

```
rakupp bin/rakuglaze                 # every snippet: failures listed, then a table per area
rakupp bin/rakuglaze subst comb      # only snippets whose id or file contains a pattern
rakupp bin/rakuglaze -v grammars     # expected/got for each failure
rakupp bin/rakuglaze -j4             # four engine processes at once (-j=4 too; default: every core)
rakudo bin/rakuglaze                 # the same suite under Rakudo
```

While it runs, a progress line on stderr (only when stderr is a terminal)
counts snippets done and not passing. A run then lists the snippets that did not pass — [WRONG] output, [CRASH] or [HANG] —
then a table per area (the directory under `glaze/`), padded so it reads in a
terminal and pastes as markdown, and exits non-zero when anything failed.

It packs a few hundred snippets into one engine process and `EVAL`s each
separately, so a parse error or an exception sinks that snippet alone; an
engine that crashes or hangs is charged to the snippet it was running, and
the rest of the process is re-run past it.

## A snippet

```
=== subset-where-any-list
from: BDD::Behave 0.9.5 lib/BDD/Behave/DocExtractor.rakumod:10
license: Artistic-2.0
feature: decl subset
--- code
my subset DocFormat of Str where { $_ eq any(<markdown html json>) };
sub render(DocFormat $f) { "as $f" }
say render('html');
say render('pdf');
--- expect
as html
!! X::TypeCheck::Binding::Parameter
```

- `from:` names the dist, its version, and the file and line the construct
  was taken from. `license:` is that dist's license; only permissive licenses
  are accepted (`bin/rakuglaze --check` enforces it).
- `--- expect` is the snippet's stdout. An exception that escapes prints as
  `!! ` and its type name — the type is compared, the message wording is not.
- Expectations are recorded from Rakudo (`rakudo bin/rakuglaze --oracle`), twice; a
  snippet whose output moves between runs is not recorded. Rakudo is the
  oracle, not the arbiter: a snippet whose expectation was ruled against
  Rakudo carries `ruled:` with the reason, and `--oracle --refresh` leaves it
  alone.
- Output must be deterministic: sort hash keys, no timings, no addresses.
- Use `my class` where the name does not matter. A global `class Foo` is
  fine — snippets declaring the same global name are run in different
  processes — but `my` keeps the packing tight. `alone: yes` gives a snippet
  (an `augment`, say) a process of its own.

## Mining

The corpus is module source read from installed stores — never committed.

```
rakupp tools/mine.raku index STORE...            # corpus/index.tsv: every lib/ file, its dist and license
rakupp tools/mine.raku features                  # corpus/features.tsv: constructs ranked by how many dists use them
rakupp tools/mine.raku --max=20 where 'PATTERN'  # real uses of a construct, one per dist
rakupp tools/mine.raku stats                     # suite size, and how much of the top-N constructs it covers
```

`features` reads each file through `rakupp --ast` (node kinds, method,
sub and operator names) plus a lexical pass for what the AST dump does not
show (traits, type smileys, regex constructs). `stats` measures the suite
against that ranking, which is how snippets are chosen: the next snippet
should cover a construct many dists use and the suite does not yet touch.

## Layout

```
bin/rakuglaze      runs the snippets on the engine that runs it; --oracle, --check
tools/mine.raku    the corpus: index, construct map, real uses, coverage
tools/pick.raku    corpus lines for a model to draft snippets from
tools/accept.raku  admits drafted snippets, or rejects each with a reason
lib/Rakuglaze/     Format (.glaze files), Fire (packing, running), Corpus (index, features)
glaze/             the snippets, one directory per area
docs/PLAN.md       where the suite is going
docs/HAIKU.md      drafting snippets with a small model: the workflow and its prompt
```
