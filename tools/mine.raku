#!/usr/bin/env rakupp
# mine.raku — the corpus side of Rakuglaze: where snippets come from.
#
#   rakupp tools/mine.raku index STORE ...                index module sources -> corpus/index.tsv
#   rakupp tools/mine.raku features                       construct map -> corpus/features.tsv
#   rakupp tools/mine.raku [--max=N] [--all] where PATTERN   real uses of a construct
#   rakupp tools/mine.raku stats                          suite size, and top-N coverage
#
# features and stats read `rakupp --ast`: under rakupp the running binary,
# under another engine the rakupp on PATH, or --rakupp=PATH. Options go
# before the words.

use lib $*PROGRAM.parent.parent.add('lib');
use Rakuglaze::Format;
use Rakuglaze::Corpus;

my $root = $*PROGRAM.parent.parent;
my $glaze = ~$root.add('glaze');
my $tmp = ~$root.add('tmp');
my $rakupp-default = $*VM.name eq 'cpp' ?? ~$*EXECUTABLE !! 'rakupp';

multi MAIN('index', *@stores) {
    my @rows = index-stores(@stores);
    mkdir $root.add('corpus');
    write-index(~$root.add('corpus/index.tsv'), @rows);
    my $dists = @rows.map(*<name>).unique.elems;
    my $ok = @rows.grep(*<permissive>).map(*<name>).unique.elems;
    say "{@rows.elems} files from $dists dists ($ok with a permissive license) -> corpus/index.tsv";
}

multi MAIN('features', Str :$rakupp = $rakupp-default) {
    my @rows = read-index(~$root.add('corpus/index.tsv')).grep(*<permissive>);
    my %dists;          # feature => SetHash of dist names
    my %where;          # feature => first "dist file"
    for @rows.kv -> $i, %r {
        note "  {$i + 1}/{+@rows}" if ($i + 1) %% 250;
        for file-features($rakupp, %r<path>) -> $f {
            %dists{$f}{%r<name>} = True;
            %where{$f} //= "%r<name> %r<file>";
        }
    }
    my @out = %dists.keys.sort({ -%dists{$_}.elems, $_ })
                .map({ join "\t", $_, %dists{$_}.elems, %where{$_} });
    spurt $root.add('corpus/features.tsv'), @out.map({ "$_\n" }).join;
    say "{+@out} features across {@rows.map(*<name>).unique.elems} dists -> corpus/features.tsv";
}

# Real uses of a construct, for mining: every code line (pod and comments
# blanked) in a permissive dist that matches PATTERN, one per dist unless
# --all.
multi MAIN('where', Str $pattern, Int :$max = 40, Bool :$all) {
    my $re = rx/<$pattern>/;
    my %seen;
    my $n = 0;
    for code-lines().lines -> $row {
        my ($name, $ver, $file, $line, $license, $code) = $row.split("\t", 6);
        next if !$all && %seen{$name};
        next unless $code ~~ $re;
        say "$name $ver $file:$line\t$license\t$code";
        %seen{$name}++;
        exit if ++$n >= $max;
    }
}

# Every non-blank code line of the permissive corpus, pod and comments
# blanked, one per row: dist, version, file, line, license, code. Built once
# from corpus/index.tsv and rebuilt when the index is newer.
sub code-lines(--> IO::Path) {
    my $index = $root.add('corpus/index.tsv');
    my $cache = $root.add('corpus/code.tsv');
    return $cache if $cache.e && $cache.modified >= $index.modified;
    # written aside and renamed into place: a concurrent `where` must never
    # read a half-built cache
    my $part = $root.add("corpus/code.tsv.$*PID");
    my $fh = $part.open(:w);
    for read-index(~$index).grep(*<permissive>) -> %r {
        for code-only(%r<path>.IO.slurp).lines.kv -> $i, $l {
            next unless $l.trim;
            $fh.say: join "\t", %r<name>, %r<ver>, %r<file>, $i + 1, %r<license>, $l.trim;
        }
    }
    $fh.close;
    $part.rename($cache);
    $cache
}

multi MAIN('stats', Str :$rakupp = $rakupp-default) {
    my @s = glaze-files($glaze).map({ |parse-glaze($_) });
    say "{+@s} snippets in {+glaze-files($glaze)} files, {+@s.grep(*.expect.defined)} with an oracle";
    my $map = $root.add('corpus/features.tsv');
    return unless $map.e;
    my %weight = $map.lines.map({ .split("\t")[0, 1] }).map({ .[0] => .[1].Int });
    my $covered = SetHash.new;
    mkdir $tmp;
    for @s -> $s {
        my $f = $tmp.IO.add("stats-{$*PID}.raku");
        spurt $f, $s.code;
        $covered{$_} = True for file-features($rakupp, ~$f);
        $f.unlink;
    }
    for 50, 100, 250, 500, 1000 -> $n {
        my @top = %weight.keys.sort({ -%weight{$_}, $_ }).head($n);
        my $hit = +@top.grep({ $covered{$_} });
        printf "  top %4d features: %4d covered (%.0f%%)\n", $n, $hit, 100 * $hit / @top.elems;
    }
}
