unit module Rakuglaze::Format;

# A .glaze file holds snippets, one after another:
#
#   === hash-kv-loop
#   from: Some::Dist 1.2.3 lib/Some/Dist.rakumod:41
#   license: Artistic-2.0
#   feature: For/.kv
#   --- code
#   my %h = a => 1;
#   for %h.sort -> (:$key, :$value) { say "$key=$value" }
#   --- expect
#   a=1
#
# Header lines are `key: value`. The `--- code` and `--- expect` blocks are
# raw lines and run to the next line that starts with `=== ` or `--- `.
# A missing `--- expect` block means the oracle has not been recorded yet.

class Snippet is export {
    has Str $.id is required;
    has Str $.file;
    has Int $.line;
    has %.meta;
    has Str $.code is rw = '';
    has Str $.expect is rw;

    method render(--> Str) {
        my $s = "=== $!id\n";
        $s ~= "$_: %!meta{$_}\n" for %!meta.keys.sort({ key-order($_) });
        $s ~= "--- code\n$!code";
        $s ~= "\n" unless $!code.ends-with("\n");
        with $!expect {
            $s ~= "--- expect\n$_";
            $s ~= "\n" unless .ends-with("\n") || !.chars;
        }
        $s
    }
}

my @order = <from license feature dists ruled>;
sub key-order($k) { @order.first($k, :k) // @order.elems ~ $k }

sub parse-glaze(Str $path --> List) is export {
    my @snippets;
    my $cur;
    my $block = '';
    my $n = 0;
    for $path.IO.lines -> $l {
        $n++;
        if $l.starts-with('=== ') {
            @snippets.push: $cur = Snippet.new(id => $l.substr(4).trim, file => $path, line => $n);
            $block = 'head';
        }
        elsif $l.starts-with('--- ') && $cur {
            $block = $l.substr(4).trim;
            die "$path:$n: unknown block '$block'" unless $block eq 'code' | 'expect';
            $cur.expect = '' if $block eq 'expect';
        }
        elsif !$cur {
            next if $l.starts-with('#') || !$l.trim;
            die "$path:$n: text before the first snippet";
        }
        elsif $block eq 'head' {
            next unless $l.trim;
            my ($k, $v) = $l.split(':', 2);
            die "$path:$n: header line without a colon" without $v;
            $cur.meta{$k.trim} = $v.trim;
        }
        elsif $block eq 'code' {
            $cur.code ~= "$l\n";
        }
        else {
            $cur.expect ~= "$l\n";
        }
    }
    # a trailing blank line belongs to the file, not to the last block
    for @snippets {
        .code = .code.subst(/\n\n+$/, "\n");
        .expect = .expect.subst(/\n\n+$/, "\n") if .expect.defined;
    }
    @snippets.List
}

sub write-glaze(Str $path, @snippets) is export {
    my $head = $path.IO.e
        ?? $path.IO.lines.toggle({ !.starts-with('=== ') }).map({ "$_\n" }).join
        !! '';
    spurt $path, $head ~ @snippets.map(*.render).join("\n");
}

sub glaze-files(Str $root = 'glaze' --> List) is export {
    my @todo = $root.IO;
    my @files;
    while @todo {
        my $d = @todo.shift;
        for $d.dir.sort -> $e {
            if $e.d { @todo.push: $e }
            elsif $e.extension eq 'glaze' { @files.push: ~$e }
        }
    }
    @files.sort.List
}
