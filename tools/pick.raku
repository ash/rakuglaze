#!/usr/bin/env rakupp
# pick.raku — choose corpus lines for a model to reduce into snippets.
#
#   rakupp tools/pick.raku --n=250 --out=tmp/haiku/batch-02.tsv
#
# Each picked line has a call SHAPE (identifiers, strings and numbers
# normalised) that no snippet in the suite has yet, no two come from the same
# dist file, and none is a line a snippet already quotes or a row handed out
# in an earlier batch (every tmp/haiku/*.tsv). Lines that cannot stand alone
# — pod, native bindings, I/O, processes, time and randomness — are left out.

use lib $*PROGRAM.parent.parent.add('lib');
use Rakuglaze::Format;

my $root = $*PROGRAM.parent.parent;

sub shape($l) {
    $l.subst(/ '"' <-["]>* '"' | "'" <-[']>* "'" /, 'S', :g)
      .subst(/ \d+ ['.' \d+]? /, 'N', :g)
      .subst(/ <[$@%&]> <[.!*]>? <[\w-]>+ /, 'V', :g)
      .subst(/ <|w> <[A..Z]> [\w|'::']* /, 'T', :g)
}

sub row-key($row) { $row.split("\t", 6)[^4].join("\t") }

sub MAIN(Int :$n = 250, Str :$out!) {
    my %used;           # dist:file:line already quoted by a snippet
    my %have;           # shapes the suite already has
    for glaze-files(~$root.add('glaze')).map({ |parse-glaze($_) }) -> $s {
        %used{$0 ~ ':' ~ $1} = True if $s.meta<from> ~~ / ^ (\S+) \s \S+ \s (\S+) /;
        %have{shape($_.trim)} = True for $s.code.lines;
    }
    my %given;          # rows already in an earlier batch
    my $batches = $root.add('tmp/haiku');
    if $batches.d {
        for $batches.dir.grep(*.extension eq 'tsv') -> $b {
            %given{row-key($_)} = True for $b.lines;
        }
    }

    my (%seen-shape, %seen-file, @out);
    for $root.add('corpus/code.tsv').lines.pick(*) -> $row {    # random order spreads the dists
        my ($dist, $ver, $file, $line, $lic, $code) = $row.split("\t", 6);
        next unless 25 <= $code.chars <= 110;
        next if $code ~~ / ^ [use|unit|need|import|'}'|'{'|'#'|'='] | ^ [has|my|our] \s+ \S+ \s* ';' $
                         | 'NativeCall' | 'is native' | 'run ' | 'shell' | '.IO' | 'spurt' | 'slurp'
                         | '%*ENV' | 'now' | 'rand' | 'sleep' | 'Proc' | 'socket'
                         | 'C<' | 'L<' | 'B<' | 'I<' | '$*VM' | 'size_t' | 'Pointer' | 'RakuAST' | 'CArray'
                         | ' ' [Returns|returns|The|the|This|If] ' ' /;
        next unless $code ~~ / '.' <[a..z]> | <[~+*\/%]> | '~~' | ' if ' | ' for ' | '//' | '»'
                             | ' Z' | ' X' | 'gather' | 'given' | 'where' /;
        next if %given{row-key($row)};
        my $sh = shape($code);
        next if %have{$sh} || %seen-shape{$sh}++ || %used{"$dist:$file:$line"};
        next if %seen-file{"$dist $file"}++;
        @out.push: $row;
        last if @out >= $n;
    }
    mkdir $out.IO.parent;
    spurt $out, @out.map({ "$_\n" }).join;
    say "{+@out} lines -> $out";
}
