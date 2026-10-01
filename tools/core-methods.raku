#!/usr/bin/env rakudo
# core-methods.raku — the method names Raku's own types have, for pick.raku:
#
#   rakudo tools/core-methods.raku > corpus/core-methods.txt
#
# Run it under Rakudo: it asks the types themselves.
my @types = Mu, Any, Cool, Str, Int, Num, Rat, FatRat, Complex, Bool, List, Array, Hash, Map, Seq,
            Range, Pair, Capture, Match, Grammar, Set, Bag, Mix, SetHash, BagHash, Junction, Code,
            Block, Routine, Sub, Method, Signature, Parameter, Version, Date, DateTime, Duration,
            Blob, Buf, Exception, Failure, Supply, Promise, Channel, Enumeration, Whatever, Regex,
            Uni, Proxy, Stringy, Numeric, Real, Iterable, Positional, Associative;
# I/O, processes, time and randomness never appear in a snippet
my $skip = set <print say put note printf print-nl connect child add parent sibling open close
                slurp spurt lines-from d e f l r w x s z dir mkdir rmdir unlink rename copy move
                chmod resolve watch roll pick grab grabpairs rand srand sleep now
                in-timezone local utc today kill run shell spawn tap emit done act>;
my %names;
for @types -> $t { %names{$_}++ for (try $t.^methods(:all).map(*.name)) // () }
.say for %names.keys.grep({ /^ <[a..z]> [\w|'-']* $/ && $_ ∉ $skip }).sort;
