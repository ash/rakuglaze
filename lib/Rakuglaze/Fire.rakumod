unit module Rakuglaze::Fire;
use Rakuglaze::Format;

# One engine process runs many snippets. Each snippet is EVAL'd on its own,
# so a parse error or an exception sinks that snippet and nothing else; a
# record separator (U+001E) and the snippet's index go to stdout before it,
# and the runner cuts stdout at those markers. An engine that dies or hangs
# mid-chunk is charged to the snippet after the last marker, and the chunk
# is restarted just past it.

my constant RS = "\x[1E]";
my $serial = 0;

# Global names a snippet declares (`class Foo`, `grammar Foo::Bar`, ...).
# Two snippets declaring the same name must not share a process: the second
# would die of X::Redeclaration, which says nothing about the construct.
sub declared-names(Str $code --> List) is export {
    $code.lines
        .grep({ !/^ \s* my \s/ })
        .map({ ~$0 if /^ \s* [our \s+]? [class|role|grammar|module|package|enum|subset] \s+ (<[\w:'-]>+)/ })
        .grep(*.defined).List
}

# Greedy packing: a snippet goes into the first chunk that holds none of its
# names and has room; `alone: yes` snippets (augment, global side effects)
# get a process to themselves.
sub chunk(@snippets, Int :$size = 400 --> List) is export {
    my @chunks;
    for @snippets -> $s {
        if ($s.meta<alone> // '') eq 'yes' {
            @chunks.push: { snippets => [$s], names => SetHash.new, alone => True };
            next;
        }
        my @names = declared-names($s.code);
        my $home = @chunks.first({ !.<alone> && .<snippets> < $size && !(.<names>{@names}.any) });
        without $home {
            @chunks.push: $home = { snippets => [], names => SetHash.new, alone => False };
        }
        $home<snippets>.push: $s;
        $home<names>{$_} = True for @names;
    }
    @chunks.map(*<snippets>.List).List
}

sub program(@snippets --> Str) is export {
    my $p = "use MONKEY-SEE-NO-EVAL;\n";
    for @snippets.kv -> $i, $s {
        $p ~= "print \"\\x[1E]$i\\n\"; \$*OUT.flush;\n";
        $p ~= "try \{ EVAL Q:to/END_GLAZE_{$i}/;\n{$s.code}END_GLAZE_{$i}\n";
        $p ~= "CATCH \{ default \{ say '!! ' ~ .^name \} \} \}\n";
    }
    $p ~= "print \"\\x[1E]end\\n\";\n";
    $p
}

# Run one chunk; returns a list of (snippet, status, output) where status is
# 'ran', 'crash' or 'hang'.
sub run-chunk(Str $engine, @snippets, Str :$tmp!, Int :$timeout = 30 --> List) is export {
    my @results;
    my @todo = @snippets;
    while @todo {
        my $file = $tmp.IO.add("glaze-{$*PID}-{$*THREAD.id}-{++$serial}.raku");
        spurt $file, program(@todo);
        # perl's alarm as the watchdog: macOS has no timeout(1)
        my $proc = run '/usr/bin/perl', '-e', 'alarm shift; exec @ARGV or exit 127',
                       ~$timeout, $engine, ~$file, :out, :err;
        my $out = $proc.out.slurp(:close);
        $proc.err.slurp(:close);
        my $exit = $proc.exitcode;
        $file.unlink;

        my @pieces = $out.split(RS);
        @pieces.shift;                          # anything before the first marker
        my $last = -1;
        my $finished = False;
        for @pieces -> $piece {
            my ($tag, $body) = $piece.split("\n", 2);
            $body //= '';
            if $tag eq 'end' { $finished = True; last }
            my $i = $tag.Int;
            @results.push: (@todo[$i], 'ran', $body);
            $last = $i;
        }
        last if $finished;
        # the engine died inside snippet $last (or before the first one)
        my $victim = $last max 0;
        if $last >= 0 {
            @results.pop;
        }
        my $status = $exit == 142 || $proc.signal == 14 ?? 'hang' !! 'crash';
        my $partial = $last >= 0 ?? @pieces[$last].split("\n", 2)[1] // '' !! '';
        @results.push: (@todo[$victim], $status, $partial);
        @todo = @todo[$victim + 1 .. *];
    }
    @results.List
}
