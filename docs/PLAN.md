# Rakuglaze plan

## Goal

Thousands of short snippets, each a construct real modules use, that run
against an engine in well under a minute — fast enough to run after every
engine change, next to Roast.

What it is not:

- not Roast — Roast specifies the language; Rakuglaze samples what the
  ecosystem leans on, weighted by how many dists lean on it;
- not Rakugrid — Rakugrid generates construct crossings; Rakuglaze only
  holds code somebody wrote and published;
- not the ecosystem sweep — the sweep installs and tests whole dists (hours,
  network, native libraries); Rakuglaze needs neither modules nor network.

## Budget

Measured on the first 44 snippets: rakupp 0.02 s, Rakudo 0.9 s (one process,
one `EVAL` each). Rakudo's `EVAL` costs about 20 ms, so 5,000 snippets take
roughly 100 s to record an oracle and a fraction of a second to run under
rakupp. The run-time budget is not the constraint; the snippet count is
limited by mining effort.

## Choosing snippets

`corpus/features.tsv` ranks constructs by the number of dists that use them.
A snippet earns its place by covering a construct with a high dist count
that the suite does not cover yet (`tools/mine.raku stats`). Within a construct,
prefer the variants modules actually use — `self.bless(|c)`,
`self.bless: :v($v)`, `multi method new(Int:D $value)` are three snippets,
not one.

## Phases

1. **Harness** — format, the runner, `--oracle`, `--check`, crash/hang recovery,
   corpus index, feature map, `where`, `stats`. Done.
2. **Seed** — hand-reduced snippets for the top constructs, to settle the
   conventions. 44 so far.
3. **Mining at scale** — work down `features.tsv`: per construct, `where`
   finds real uses, each is reduced to a standalone snippet and recorded.
   Target: the top 500 constructs covered, then every construct used by 5+
   dists (about 800).
4. **Whole corpus** — the index currently reads the stores of the last
   ecosystem sweep (607 dists). The full ecosystem (about 2,500 dists) needs
   its sources fetched; the sweep's REA metadata names them.
5. **Module tests as a source** — `t/` files carry ready-made expectations
   (`is`/`ok` lines). The stores do not keep them; fetching sources (phase 4)
   brings them in.
6. **Parse tier** — every `lib/` file in the corpus, parsed but not run,
   catches parser regressions across the ecosystem at once. Needs a parse
   mode that does not load `use`d modules on every engine compared.

## Open questions

- A repository license for the tooling, and the attribution notice for the
  quoted snippets.
- Whether the runner should run chunks in parallel (it is already fast enough
  serially under rakupp).
