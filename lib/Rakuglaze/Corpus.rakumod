unit module Rakuglaze::Corpus;
use JSON::Fast;

# The corpus is the module source the snippets are mined from. It is read
# from installed stores (a `dist/` of META files plus `sources/` named by
# hash), indexed into corpus/index.tsv, and never committed: only the short
# snippets that come out of it are.

# Licenses whose code may be quoted in a public repo with attribution.
my @permissive = <
    Artistic-2.0 Artistic-1.0-Perl MIT BSD-2-Clause BSD-2-Clause-FreeBSD
    BSD-3-Clause ISC Unlicense CC0-1.0 Apache-2.0 X11 Zlib 0BSD
>;
sub permissive(Str $license --> Bool) is export {
    my $l = $license.trim;
    return True if $l eq 'Artistic License 2.0'
                || $l eq 'http://www.perlfoundation.org/artistic_license_2_0';
    so $l.split(/\s+ [AND|OR] \s+/).all ∈ @permissive
}

sub index-stores(@stores --> List) is export {
    my %best;           # name => META, the newest version seen
    for @stores -> $store {
        for $store.IO.add('dist').dir -> $m {
            my %meta = from-json($m.slurp);
            my $name = %meta<name> // next;
            my $ver = Version.new(%meta<ver> // %meta<version> // '0');
            next if %best{$name} && (%best{$name}<ver> cmp $ver) != Less;
            %best{$name} = { :$ver, :$store, :%meta };
        }
    }
    my @rows;
    for %best.keys.sort -> $name {
        my %b = %best{$name};
        my %files = %b<meta><files> // {};
        my $license = %b<meta><license> // '';
        for %files.keys.grep(*.starts-with('lib/')).sort -> $file {
            my $path = %b<store>.IO.add('sources').add(%files{$file});
            next unless $path.e;
            @rows.push: { :$name, ver => ~%b<ver>, :$license, :$file,
                          path => ~$path.absolute, permissive => permissive($license) };
        }
    }
    @rows.List
}

my @cols = <name ver license permissive file path>;

sub write-index(Str $to, @rows) is export {
    spurt $to, @rows.map({ @cols.map(-> $c { $c eq 'permissive' ?? +.{$c} !! .{$c} }).join("\t") ~ "\n" }).join;
}

sub read-index(Str $from --> List) is export {
    $from.IO.lines.map({
        my %r = @cols Z=> .split("\t");
        %r<permissive> = %r<permissive> eq '1';
        %r
    }).List
}

# Source with pod and `#` comments blanked out, so English prose ("this is
# safe") does not read as a trait. Line numbers are kept.
sub code-only(Str $src --> Str) is export {
    my $mode = '';          # '' code, 'block' inside =begin/=pod, 'para' abbreviated pod
    $src.lines.map(-> $l {
        if $mode eq 'block' {
            $mode = '' if $l ~~ /^ \s* ['=end' | '=cut'] /;
            ''
        }
        elsif $mode eq 'para' && $l.trim {
            ''
        }
        elsif $l ~~ /^ \s* '=finish' / {
            last
        }
        elsif $l ~~ /^ \s* '=' (<[a..zA..Z]> \w*) / {
            $mode = ~$0 eq 'begin' | 'pod' ?? 'block' !! 'para';
            ''
        }
        else {
            $mode = '';
            $l.subst(/ [^ | <after \s>] '#' <![`(\{\[\<]> \N* $/, '')
        }
    }).join("\n")
}

# `is` traits worth a feature of their own; anything else in `is X` position
# is as likely to be prose inside a string.
my @core-traits = <
    export copy rw required native repr raw built hidden-from-backtrace default
    implementation-detail pure cached DEPRECATED nodal tighter looser equiv assoc
    dynamic readonly symbol encoded test-assertion item nativeconv mangled
>;

# A file's features: what the engine's AST dump names (node kinds, and the
# method, sub and operator names on them), plus a lexical pass for what the
# dump does not show (traits, type smileys, regex constructs).
my %labelled = MethodCall => 'method', Call => 'call', Binary => 'infix',
               Unary => 'prefix', Postfix => 'postfix';

sub file-features(Str $engine, Str $path --> List) is export {
    my $p = run $engine, '--ast', $path, :out, :err;
    my $ast = $p.out.slurp(:close);
    $p.err.slurp(:close);
    my %f;
    for $ast.lines -> $l {
        next unless $l ~~ /^ \s* (<[A..Z]> \w+) \s* [ '│' \s* (\S+) ]? /;
        my $kind = ~$0;
        if %labelled{$kind} -> $what {
            my $name = ~($1 // next);
            $name .= substr(1) if $kind eq 'MethodCall' && $name.starts-with('.');
            next unless $name ~~ /^ <[\w:<>\[\]'\-+*\/%~=!?.^&|]>+ $/;
            %f{"$what $name"} = True;
        }
        else {
            %f{"node $kind"} = True;
        }
    }
    my $src = code-only($path.IO.slurp);
    # a trait follows a declared name, a variable or a closing paren/bracket
    my token target { [ <[$@%&]> <[.!*]>? <[\w-]>+ | <[\w:-]>+ | ')' | ']' | '>' ] }
    for $src.lines.grep(/« [has|my|our|sub|method|submethod|class|role|grammar|module|multi|proto|token|rule|regex|constant|enum|subset] »|<[$@%]>\w/) -> $l {
        %f{"trait is $_"} = True for $l.comb(/ <target> \s+ is \s+ <( <[a..zA..Z]> [\w|'-']+ /).grep(* ∈ @core-traits);
        %f{"trait $_"} = True for $l.comb(/ <target> \s+ <( [does|handles|returns] <before \s+ <[\w:$&(\<\'"]> > /);
        %f{"trait will $_"} = True for $l.comb(/ <target> \s+ will \s+ <( \w+ <before \s* '{'> /);
    }
    %f{'smiley :D'} = True if $src ~~ / <[\w\]]> ':D' >> /;
    %f{'smiley :U'} = True if $src ~~ / <[\w\]]> ':U' >> /;
    %f{'return -->'} = True if $src.contains('-->');
    %f{"decl $_"} = True for $src.comb(/ ^^ \s* <( [token|rule|regex|proto|multi|submethod|enum|subset|constant] >> /).unique;
    %f{"regex $_"} = True for $src.comb(/ '<' <( ['?before'|'!before'|'?after'|'!after'|'.ws'|'ws'|'alpha'|'digit'|'ident'|'-['|'+['|'['] /).unique;
    %f{'regex %% separator'} = True if $src ~~ / <[*+?]> \s* '%%' /;
    %f{'regex % separator'}  = True if $src ~~ / <[*+]> \s* '%' \s+ /;
    %f{'regex <( )>'} = True if $src.contains('<(') && $src.contains(')>');
    %f{'regex make'} = True if $src ~~ / « make \s /;
    %f{"phaser $_"} = True for $src.comb(/ « <( [BEGIN|INIT|END|ENTER|LEAVE|KEEP|UNDO|FIRST|NEXT|LAST|PRE|POST|CATCH|CONTROL|QUIT|CLOSE|TWEAK|BUILD] \s* '{' /).map(*.subst(/\s*'{'/, '')).unique;
    %f.keys.sort.List
}
