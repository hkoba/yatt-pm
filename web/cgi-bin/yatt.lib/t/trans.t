#!/usr/bin/perl -w
# -*- mode: perl; coding: utf-8 -*-
use strict;
use warnings FATAL => qw(all);
use FindBin;
use lib "$FindBin::Bin/..";
use YATT::Test qw(no_plan);

#========================================
my $TRANS = 'YATT::Translator::Perl';
require_ok($TRANS);

my $SECTION = 0;
my $tmpdir = tmpbuilder(rootname($0) . ".tmp");

if (0) {
  $SECTION++;
  my ($test) = 'index.html, widget';
  my $DIR = $tmpdir->
    ([DIR => "doc",
      [FILE => 'index.html',
       q{<h2>(<perl:wfoo x=&perl:args:title;
z=&perl:args:note;
/>)</h2><perl:widget
 wfoo x y z/><u>&perl:x; + &perl:z;</u>}],
     ],
    );
  my $top = YATT::Toplevel->new([DIR => "$DIR/doc", LIB => "$DIR/lib"]);

  is capture {
    $top->evaluate([path => [render => 'index']]
		   , {title => 'bar', note => 'bazz'})
  }, "<h2>(<u>bar + bazz</u>)</h2>", 'widget wfoo';
}

if (0) {
  $SECTION++;
  my ($test) = 'index.html, widget';
  my $DIR = $tmpdir->([DIR => "doc"
		       , [FILE => '.htyattrc', <<'END']
Entity sum => sub {
  my ($this) = shift;
  my $sum = 0;
  $sum += $_ for @_;
  $sum;
};
END
		      ]);

  my $top = YATT::Toplevel->new([DIR => "$DIR/doc", auto_reload => 1]);
  my $fn;

  #
  $tmpdir->build($DIR, [DIR => "doc", [FILE => 'index.html', <<'END']]);
<:perl:args x=text y=value
/><h2>&perl:x; + &perl:y; = <?perl= $x + $y?></h2>
END
  is capture {
    $top->evaluate([path => [render => $fn = 'index']]
		   , {x => 3, y => 8})
  }, "<h2>3 + 8 = 11</h2>\n", $fn;

  #
  $tmpdir->build($DIR, [DIR => "doc"
			, [FILE => ($fn = 'entpath1.html'), <<'END']]);
3+4+5=&perl:sum(=3..5);
END
  is capture {
    $top->evaluate([path => [render => basename(rootname($fn))]])
  }, "3+4+5=12\n", $fn;

  #
  $tmpdir->build($DIR, [DIR => "doc", [FILE => 'callindex.html'
				       , q(<perl:index y=7 x=5/>)]]);
  is capture {
    $top->evaluate([render => $fn = 'callindex'])
  }, "<h2>5 + 7 = 12</h2>\n", $fn;


  #
  $tmpdir->build($DIR, [DIR => "doc", [FILE => 'wtest.html', <<'END']]);
<h2><perl:woo a=abc b=def>ghi</perl:woo></h2><:perl:widget
 woo a b=text/>&perl:a;/&perl:b;/<perl:body />
END
  is capture {
    $top->evaluate([render => $fn = 'wtest'])
  }, "<h2>abc/def/ghi\n</h2>", $fn;


  #
  $tmpdir->build($DIR, [DIR => "doc", [FILE => 'wonly.html', <<'END']]);
<perl:widget foo/>
<perl:widget bar/>
END
  is capture {
    $top->evaluate([render => $fn = 'wonly'])
  }, "", $fn;

  is capture {
    $top->evaluate([render => $fn = 'wtest', 'woo']
		   , {a => "foo", b => "bar"})
  }, "foo/bar/\n", "$fn woo";

  is capture {
    $top->evaluate([render => $fn = 'wtest', 'woo']
		   , {a => "1", b => "2"}
		   , sub {print "hoehoe"})
  }, "1/2/hoehoe\n", "$fn woo body";


  #
  $tmpdir->build($DIR, [DIR => "doc", [FILE => 'if_test.html', <<'END']]);
<:perl:args a limit offset mul
/><h2><perl:ifte
  limit="&perl:limit;"
  value='&perl:a; + &perl:offset;'
  cond="&perl:a; * &perl:mul; > &perl:limit;"
/></h2>
<:perl:widget ifte cond=expr value=value limit=value
/><perl:if if="&perl:value; < &perl:limit;"
>&perl:value; is under limit &perl:limit;
<:perl:else if=&perl:do:cond;
/>cond is ok
<:perl:else
/>otherwise
</perl:if>
END
  is capture {
    $top->evaluate([render => $fn = 'if_test']
		   , {limit => 10, a => 3, mul => 3, offset => 5})
  }, "<h2>8 is under limit 10\n\n</h2>\n", "$fn then";

  is capture {
    $top->evaluate([render => $fn = 'if_test']
		   , {limit => 10, a => 3, mul => 4, offset => 8})
  }, "<h2>cond is ok\n\n</h2>\n", "$fn elsif";

  is capture {
    $top->evaluate([render => $fn = 'if_test']
		   , {limit => 10, a => 3, mul => 3, offset => 8})
  }, "<h2>otherwise\n\n</h2>\n", "$fn otherwise";


  #
  $tmpdir->build($DIR, [DIR => "doc", [FILE => 'foreach.html', <<'END']]);
<perl:ulist list="[1..3]"
/><:perl:widget ulist list=value
/><perl:if if="@&perl:list;"><ul>
<perl:foreach list="@&perl:list;"
><li>&perl:_;</li>
</perl:foreach></ul>
</perl:if>
END
  is capture {
    $top->evaluate([render => $fn = 'foreach'])
  }, "<ul>\n<li>1</li>\n<li>2</li>\n<li>3</li>\n</ul>\n\n"
    , $fn;


  #
  $tmpdir->build($DIR, [DIR => "doc", [FILE => 'foreach2.html', <<'END']]);
<perl:ulist list="[1..3]"
/><:perl:widget ulist list=value
/><perl:if if="@&perl:list;"><ul>
<perl:foreach my=i &perl:expand:list;
><li>&perl:i;</li>
</perl:foreach></ul>
</perl:if>
END
  is capture {
    $top->evaluate([render => $fn = 'foreach2'])
  }, "<ul>\n<li>1</li>\n<li>2</li>\n<li>3</li>\n</ul>\n\n"
    , $fn;

  #
  $tmpdir->build($DIR, [DIR => "doc", [FILE => 'foreach3.html', <<'END']]);
<perl:prefixed my:var list="[1..3]"
>* 2 = <?perl= $var * 2?></perl:prefixed>
<:perl:widget prefixed var=var suffix=code list=value
/><perl:foreach var="&perl:var;" list="&perl:expand:list;"
><?perl= $$var?> <perl:body/>&perl:do:suffix;
</perl:foreach>
END
  is capture {
    $top->evaluate([render => $fn = 'foreach3'])
  }, "1 * 2 = 2\n2 * 2 = 4\n3 * 2 = 6\n\n\n"
    , $fn;

  #
  $tmpdir->build($DIR, [DIR => "doc", [FILE => 'foreach4.html', <<'END']]);
<perl:prefixed my:var list="[1..3]"
>* 2 = <:perl:suffix><?perl= $var * 2
?></:perl:suffix></perl:prefixed>
<:perl:widget prefixed var=var suffix=code list=value
/><perl:foreach var="&perl:var;" list="&perl:expand:list;"
><?perl= $$var?> <perl:body/>&perl:do:suffix;
</perl:foreach>
END
  is capture {
    $top->evaluate([render => $fn = 'foreach4'])
  }, "1 * 2 = 2\n2 * 2 = 4\n3 * 2 = 6\n\n\n"
    , $fn;


  #
  $tmpdir->build($DIR, [DIR => "doc", [FILE => 'my.html', <<'END']]);
<perl:args url title
/><perl:my link><a href="&perl:url;">&perl:title;</a></perl:my
>&perl:link;
END
  is capture {
    $top->evaluate([render => $fn = 'my']
		   , {title => "test of <u>my</u>", url => "/"})
  }, qq|<a href="/">test of &lt;u&gt;my&lt;/u&gt;</a>\n|
    , $fn;

  #
  $tmpdir->build($DIR, [DIR => "doc", [FILE => 'my2.html', <<'END']]);
<perl:args url title
/><perl:foo url="&perl:url;" title="&perl:title;"
><:perl:footer><u>&copy; foobar &perl:title;</u></:perl:footer
>You can see &perl:title; in &perl:url;</perl:foo>

<perl:widget foo url title footer=code
/><perl:my baz><a href="&perl:url;">&perl:title;</a></perl:my
><h2>&perl:baz;</h2>
<p><perl:body/></p>
&perl:do:footer;
END
  is capture {
    $top->evaluate([render => $fn = 'my2']
		   , {title => "test of html type", url => "/"})
  }, qq|<h2><a href="/">test of html type</a></h2>
<p>You can see test of html type in /</p>
<u>&copy; foobar test of html type</u>\n\n\n|
    , $fn;

  #
  $tmpdir->build($DIR, [DIR => "doc", [FILE => 'form1.html', <<'END']]);
<:perl:args qname=attr?name list=value
/><form>
<perl:foreach my=value list="&perl:expand:list;"
><input type="radio" &perl:qname; value="&perl:value;">
</perl:foreach
></form>
END
  is capture {
    $top->evaluate([render => $fn = 'form1']
		   , {qname => 'q1', list => [1 .. 3, q|")&foo("|]})
  }, <<'END'
<form>
<input type="radio" name="q1" value="1" />
<input type="radio" name="q1" value="2" />
<input type="radio" name="q1" value="3" />
<input type="radio" name="q1" value="&quot;)&amp;foo(&quot;" />
</form>
END
      , $fn;

  #
  $tmpdir->build($DIR, [DIR => "doc", [FILE => 'selfref.html', <<'END']]);
<:perl:args x=value y=value
/><perl:bar x="&perl:x;" y="&perl:y;"
/><perl:widget foo x=value y=value
/>&perl:x; + &perl:y; = <?perl= $x + $y?><:perl:widget bar x=value y=value
/><perl:selfref:foo x="&perl:x;" y="&perl:y;"/>
END
  is capture {
    $top->evaluate([render => $fn = 'selfref'], {x => 3, y => 8})
  }, "3 + 8 = 11\n", $fn;


  #
  $tmpdir->build($DIR, [DIR => "doc", [FILE => 'pi.html', <<'END']]);
<?perl= 'foo'?>
END
  is capture {
    $top->evaluate([render => $fn = 'pi'])
  }, "foo\n", $fn;
}

if (0) {
  $SECTION++;
  my ($test) = 'calling conv, default';
  my $DIR = $tmpdir->
    ([DIR => "doc"
      , [FILE => 'index.html', <<'END']
<perl:foo /><perl:foo bar=3/><perl:foo baz=4
/><perl:foo name="foo"/><perl:foo morename="bar"/>

<perl:widget foo bar=?BAR baz=text?BAZ name=attr morename=attr?name
/>&perl:bar;-&perl:baz;<x&perl:name;/><y&perl:morename;/>
END

      , [FILE => 'precise.html', <<'END']
<perl:foo
/><perl:foo slash='' ques='' vbar=''
/><perl:foo slash=0 ques=0 vbar=0/>

<perl:widget foo slash=/s ques=?q vbar=|b
/>&perl:slash;-&perl:ques;-&perl:vbar;
END
      ]);

  my $top = YATT::Toplevel->new([DIR => "$DIR/doc", LIB => "$DIR/lib"]);
  my $fn;

  is capture {
    $top->evaluate([render => $fn = 'index'])
  }, qq|BAR-BAZ<x/><y/>
3-BAZ<x/><y/>
BAR-4<x/><y/>
BAR-BAZ<x name="foo"/><y/>
BAR-BAZ<x/><y name="bar"/>
\n\n|, "$test. $fn";

  is capture {
    $top->evaluate([render => $fn = 'precise'])
  }, "s-q-b\n-q-b\n0-0-b\n\n\n", "$test. $fn";
}

if (0) {
  $SECTION++;
  my ($test) = 'calling conv, loop var';
  my $DIR = $tmpdir->
    ([DIR => "doc"
      , [FILE => 'index.html', <<'END']
<perl:tacit my:var=row list="[[1, 'foo'], [2, 'bar']]"
><td>&perl:row[0];</td>
<td>&perl:row[1];</td>
</perl:tacit>

<perl:widget tacit var=var list=value
/><perl:table &perl:var; &perl:list; class=tacit cellpadding=3
 rowclass=flat
><perl:body/></perl:table>

<perl:widget table var=var list=value
  rowclass=attr?class
  class=attr
  cellspacing=attr
  cellpadding=attr
  border=attr
/><table&perl:class;&perl:cellspacing;&perl:cellpadding;&perl:border;>
<perl:foreach var=&perl:var; &perl:expand:list;><tr&perl:rowclass;>
<perl:body/></tr>
</perl:foreach></table>
END

     ]
    );

  my $top = YATT::Toplevel->new([DIR => "$DIR/doc", LIB => "$DIR/lib"]);
  my $fn;

  run($test, sub {
	eq_or_diff capture {
	  $top->evaluate([path => [render => $fn = 'index']], {});
	}, <<'END' . "\n" x 4, $test;
<table class="tacit" cellpadding="3">
<tr class="flat">
<td>1</td>
<td>foo</td>
</tr>
<tr class="flat">
<td>2</td>
<td>bar</td>
</tr>
</table>
END
      });
}

if (0) {
  $SECTION++;
  my ($test) = 'entity';
  my $DIR = $tmpdir->
    ([DIR => "doc"
      , [FILE => 'index.html', <<'END']
<:perl:args hash x y/>&perl:hash:$x/$y;
END

     ]);
  my $top = YATT::Toplevel->new([DIR => "$DIR/doc", LIB => "$DIR/lib"]);
  my $fn;

  eq_or_diff capture {
    $top->evaluate([path => [render => $fn = 'index']]
		   , {x => "foo", y => "bar", hash => {"foo/bar" => "baz"}})
  }, "baz\n", $test;
}

if (0) {
  $SECTION++;
  my ($test) = 'refactoring out to subdir';
  my $DIR = $tmpdir->
    ([DIR => "doc"
      , [FILE => '.htyattrc', q{
Entity null_iota => sub {
  my ($this, $num) = @_;
  (undef, map {[$_]} 1 .. $num);
};
}]
      , [FILE => 'index.html', <<'END']
<:perl:args title author
/><perl:common:envelope title author
>Hello world!</perl:common:envelope>
END

      , [FILE => 'list.html', <<'END']
<ul>
<perl:foreach my=rec list="grep {defined} &perl:null_iota(3);"
><li>&perl:rec[0];</li>
</perl:foreach></ul>
END
      , [DIR => "common"
	 , [FILE => 'envelope.html', <<'END']
<:perl:args title author/>
<html>
<head><title>&perl:title;</title></head>
<body>
<h2>&perl:title;</h2>
<perl:content><perl:body/></perl:content>
<perl:copyright author/></body>
</html>
<:perl:widget content
/><div id="content"><perl:body/></div><:perl:widget copyright author
/><p id="copyright">&copy; &perl:author;</p>
END

	 ]
     ]);

  my $top = YATT::Toplevel->new([DIR => "$DIR/doc", LIB => "$DIR/lib"]);
  my $fn;

  eq_or_diff capture {
    $top->evaluate([path => [render => $fn = 'index']]
		   , {title => 'subdir test', author => "Me."})
  }, qq{
<html>
<head><title>subdir test</title></head>
<body>
<h2>subdir test</h2>
<div id="content">Hello world!</div>
<p id="copyright">&copy; Me.</p>
</body>
</html>\n\n}, $test;

  eq_or_diff capture {
    $top->evaluate([path => [render => $fn = 'list']])
  }, <<END, 'text_with_entities raw';
<ul>
<li>1</li>
<li>2</li>
<li>3</li>
</ul>
END
}

if (0) {
  $SECTION++;
  my ($test) = 'entity_path';
  my $DIR = $tmpdir->([DIR => "doc"]);
  my $top = YATT::Toplevel->new([DIR => "$DIR/doc", auto_reload => 1]);
  my $fn;

  $tmpdir->build($DIR, [DIR => "doc", [FILE => 'index.html', <<'END']]);
<perl:foo arg:x arg:y baz='hoe'>x=&perl:x; y=&perl:y;</perl:foo>
<perl:widget foo baz/>
<h2>&perl:body(bar,:baz);</h2>
END
  is capture {
    $top->evaluate([path => [render => $fn = 'index']])
  }, "\n<h2>x=bar y=hoe</h2>\n\n", "$test. $fn";

}


if (0) {
  $SECTION++;
  my ($test) = 'entity_path cascade';
  my $DIR = $tmpdir->([DIR => "doc"
		      , [FILE => '.htyattrc', <<'END']
Entity iota => sub {my $this = shift; 1 .. shift};
Entity random => sub {
  my ($this, @list) = @_;
  my @result;
  push @result, splice @list, rand(@list), 1 while @list;
  @result;
};
Entity nsort => sub {
  my ($this) = shift;
  sort {$a <=> $b} @_;
};
END
		      ]);
  my $top = YATT::Toplevel->new([DIR => "$DIR/doc", auto_reload => 1]);
  my $fn;

  $tmpdir->build($DIR, [DIR => "doc", [FILE => 'index.html', <<'END']]);
<ul>
<perl:foreach &perl:iota(3):random():nsort();><li>&perl:_;
</perl:foreach
></ul>
END
  is capture {
    $top->evaluate([path => [render => $fn = 'index']])
  }, "<ul>\n<li>1\n<li>2\n<li>3\n</ul>\n", "$test. $fn";

  $tmpdir->build($DIR, [DIR => "doc", [FILE => 'bydot.html', <<'END']]);
<ul>
<perl:foreach &perl.iota(3).random().nsort();><li>&perl:_;
</perl:foreach
></ul>
END
  is capture {
    $top->evaluate([path => [render => $fn = 'bydot']])
  }, "<ul>\n<li>1\n<li>2\n<li>3\n</ul>\n", "$test. $fn";

}

if (0) {
  $SECTION++;
  my ($test) = 'body pass thru';
  my $DIR = $tmpdir->([DIR => "doc"]);
  my $top = YATT::Toplevel->new([DIR => "$DIR/doc", auto_reload => 1]);
  my $fn;

  $tmpdir->build($DIR, [DIR => "doc", [FILE => 'index.html', <<'END']]);
<perl:foo x=3><h2>bar</h2></perl:foo>
<perl:widget foo x />
<perl:bar x>
<:perl:y/><b>8</b>
</perl:bar>

<perl:widget bar x y=html/>
(&perl:x; + &perl:y;) &perl:body();
END
  is capture {
    $top->evaluate([path => [render => $fn = 'index']])
  }, "\n\n(3 + <b>8</b>\n) <h2>bar</h2>\n\n\n\n", "$test. $fn";
}
