#!/usr/bin/env rakupp
# accept.raku — admit model-written snippets into the suite, or reject them
# with a reason. The model drafts; this decides.
#
#   rakupp tools/accept.raku --batch=BATCH.tsv --name=NAME DRAFT.glaze
#   rakupp tools/accept.raku --batch=BATCH.tsv --dry DRAFT.glaze   # what Rakudo prints, and why each would be rejected; writes nothing
#
# BATCH.tsv is the pick.raku file the draft was written from. Accepted
# snippets land in glaze/haiku/NAME.glaze with expectations recorded fresh by
# Rakudo; rejected ones go to tmp/haiku/NAME.rejected.glaze, each under a
# `# rejected:` line. Run it under rakupp; it calls `rakudo` for the oracle.
#
# A snippet is rejected when:
#   - its `from:` is not a row of the batch, or its license differs from the row's
#   - another snippet already took that row, or the suite has the same code
#   - it reads the clock, randomness or the environment
#   - Rakudo leaves it unrecorded (dead or unstable), or it prints nothing
#   - it throws where its row does not: that records the drafter's mistake
#   - its expectation is a compile-time error: the module line compiled in
#     its module, so a snippet that does not compile tests the model's mistake
#   - it drifted: the row's line uses core methods or operators and the
#     snippet keeps none of them
# Any `--- expect` the draft carries is thrown away: only Rakudo writes one.

use lib $*PROGRAM.parent.parent.add('lib');
use Rakuglaze::Format;
use Rakuglaze::Fire;

my $root = $*PROGRAM.parent.parent;

sub norm($code) { $code.lines».trim.grep(*.chars).join("\n") }

# core method names: used by ten or more dists in the construct map
sub core-methods(--> Set) {
    my $map = $root.add('corpus/features.tsv');
    return set() unless $map.e;
    $map.lines.map({ .split("\t") }).grep({ .[0].starts-with('method ') && .[1].Int >= 10 })
        .map({ .[0].substr(7) }).Set
}
my @word-ops = <x xx eq ne lt gt le ge leg cmp div mod gcd lcm andthen orelse
                notandthen with without given when gather take repeat until
                unless where but does handles min max so not>;
my @sym-ops = '~~', '!~~', '//', '~=', '//=', '||=', '&&=', '**', '%%', '...', '^..', '..^',
               '»', '«', '+&', '+|', '+^', '?? ', ' Z ', ' X ', 'Z[', 'X[', 'Z=>', 'X~';

# the constructs a line uses, read from its code and never from its strings
sub construct-tokens($l, Set $core) {
    my $line = $l.subst(/ '"' <-["]>* '"' | "'" <-[']>* "'" /, '""', :g);
    my @t = $line.comb(/ '.' <( <[a..z]> [\w|'-']* /).grep({ $_ ∈ $core });
    @t.append: $line.comb(/ « (@word-ops) » /).map(~*);
    @t.append: @sym-ops.grep({ $line.contains($_) });
    @t.unique
}

sub MAIN(Str $draft, Str :$batch!, Str :$name, Bool :$dry) {
    die "--name is required unless --dry\n" unless $name || $dry;
    my %row;
    for $batch.IO.lines {
        my ($d, $v, $f, $l, $lic, $code) = .split("\t", 6);
        %row{"$d $v $f:$l"} = { :$lic, :$code };
    }
    my %existing = glaze-files(~$root.add('glaze'))
        .grep({ !$name || !.ends-with("haiku/$name.glaze") })
        .map({ |parse-glaze($_) }).map({ norm(.code) => True });
    my $core = core-methods();

    my (@keep, @reject, %taken);
    sub reject($s, $why) { @reject.push: ($s, $why) }
    for parse-glaze($draft) -> $s {
        $s.expect = Str;
        my $r = %row{$s.meta<from> // ''};
        if !$r                                    { reject($s, 'from: is not a row of the batch'); next }
        if ($s.meta<license> // '') ne $r<lic>    { reject($s, "license is not the row's ($r<lic>)"); next }
        if %taken{$s.meta<from>}++                { reject($s, 'a second snippet for the same row'); next }
        if %existing{norm($s.code)}               { reject($s, 'the suite already has this code'); next }
        # two runs a second apart agree, two runs a day apart do not
        if $s.code ~~ / « [now|today|rand|srand|time] » | '.' [pick|roll] » | '%*ENV' | '$*PID' / {
            reject($s, 'reads the clock, randomness or the environment'); next
        }
        my @t = construct-tokens($r<code>, $core);
        if @t && !@t.first(-> $t { $t ~~ /^ \w+ $/ ?? $s.code ~~ / « $t » / !! $s.code.contains($t) }) {
            reject($s, "drifted: keeps none of {@t.join(' ')}"); next
        }
        @keep.push: $s;
    }

    # Rakudo records each snippet twice; output that moves is not a test
    note "running {+@keep} snippets on Rakudo…";
    my $tmp = ~$root.add('tmp');
    mkdir $tmp;
    sub record() { chunk(@keep).map({ |run-chunk('rakudo', $_, :$tmp, timeout => 60) }).map({ .[0].id => .[1, 2] }).Hash }
    my %a = record();
    my %b = record();
    my @final;
    for @keep -> $s {
        my ($st, $out) = |(%a{$s.id} // ('lost', ''));
        my $why = do {
            if $st ne 'ran'                      { "Rakudo: $st" }
            elsif %b{$s.id}[1] ne $out           { 'output differs between two runs' }
            elsif !$out.trim                     { 'prints nothing' }
            elsif $out.lines.first(*.starts-with('=== ' | '--- ')) { 'prints a line the .glaze format would read as a header' }
            elsif $out ~~ / '!! X::' [Syntax|Comp|Undeclared|Redeclaration|Obsolete|Placeholder|Parameter::Default] / {
                "its expectation is a compile error ({$out.lines.first(*.starts-with('!! '))})"
            }
            # a module line that does not throw, turned into a snippet that
            # does, records the drafter's mistake rather than the construct
            elsif ($out.lines.first(*.starts-with('!! ')) // '')
                  && %row{$s.meta<from>}<code> !~~ / « [die|fail|throw|try|CATCH|Failure|X] » / {
                "throws ({$out.lines.first(*.starts-with('!! ')).substr(3)}) where its row does not"
            }
            else { Nil }
        };
        if $dry {
            say "=== {$s.id}";
            print $out.lines.map({ "    $_\n" }).join;
            say "    PROBLEM: $why" with $why;
        }
        with $why { reject($s, $_); next }
        $s.expect = $out;
        @final.push: $s;
    }
    if $dry {
        for @reject.grep({ !.[1].starts-with('Rakudo') }) -> ($s, $why) {
            say "=== {$s.id}\n    PROBLEM: $why" unless @keep.first(* === $s);
        }
        say "\n{+@final} would be accepted, {+@reject} rejected";
        return;
    }
    my $target = $root.add("glaze/haiku/$name.glaze");
    mkdir $target.parent;
    write-glaze(~$target, @final);

    my $rej = $root.add("tmp/haiku/$name.rejected.glaze");
    mkdir $rej.parent;
    spurt $rej, @reject.map(-> ($s, $why) { "# rejected: $why\n" ~ $s.render }).join("\n");

    my %why = @reject.map(*[1].subst(/ \s* '(' .* $/, '').subst(/ ':' .* $/, '')).Bag;
    say "{+@final} accepted -> glaze/haiku/$name.glaze";
    say "{+@reject} rejected -> tmp/haiku/$name.rejected.glaze";
    say "  {.value}  {.key}" for %why.sort(-*.value);
}
