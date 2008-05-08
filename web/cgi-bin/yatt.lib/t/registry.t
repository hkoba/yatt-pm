#!/usr/bin/perl -w
# -*- mode: perl; coding: utf-8 -*-
use strict;
use warnings FATAL => qw(all);
use strict;
use warnings FATAL => qw(all);
use FindBin;
use lib "$FindBin::Bin/..";
use YATT::Test qw(no_plan);

require_ok('YATT::Registry');
&YATT::break_translator;

my $TMPDIR = tmpbuilder(rootname($0) . ".tmp");

my $SESSION = 1;
{
  my $DIR = $TMPDIR->([DIR => 'foo'
		       , [FILE => 'bar.html', q{<h2>bar.html</h2>}]],
		      [FILE => 'foo.html'
		       , q{<!yatt:widget bar>}]);

  my $root = new YATT::Registry(loader => [DIR => $DIR]
			       , auto_reload => 1);
  is $root->cget('age'), 1, "[$SESSION] root age";
  is_deeply [$root->list_ns], [qw(foo)], "[$SESSION] list_ns";
  run("[$SESSION] wid_by_nsname - no error", sub {
	is defined($root->widget_by_nsname($root, qw(foo bar))), 1
	  , "[$SESSION] wid_by_nsname";
      });

  is $root->cget('age'), 1, "[$SESSION] root age";
}

# [2]
{
  $SESSION++;
  my $DIR = $TMPDIR->([DIR => 'app'
		       , [FILE => 'foo.html', q{<h2>foo</h2>}]],
		      [DIR => 'lib1'
		       , [FILE => 'bar.html', q{<h2>bar</h2>}]]);

  my $root = new YATT::Registry(loader => [DIR => "$DIR/app"
					   , LIB => "$DIR/lib1"]
			       , auto_reload => 1);
  is_deeply [sort $root->list_ns], [qw(bar foo)], "[$SESSION] list_ns";
}

# [3]
{
  $SESSION++;
  my $DIR = $TMPDIR->
    ([DIR => 'app'
      , [FILE => '.htyattrc'
	 , q{use YATT::Registry base => '/normal'; sub foo {"FOO"}}]
      , [FILE => 'index.html', q{<h2>foo</h2>}]],
     [DIR => 'lib1'
      , [DIR => 'normal'
	 , [FILE => '.htyattrc', q{sub bar {"BAR"}}]
	 , [FILE => 'bar.html', q{<h2>bar</h2>}]]]);

  my $root = new YATT::Registry
    (loader => [DIR => "$DIR/app", LIB => "$DIR/lib1"]
     , app_prefix => "MyApp$SESSION"
     , auto_reload => 1);
  is_deeply [sort $root->list_ns], [qw(index normal)]
    , "[$SESSION] base => /normal";

  isnt my $index = $root->get_ns(['index']), undef, "[$SESSION] index";
  isnt $root->get_widget_from_template($index, qw(yatt bar)), undef
    , "[$SESSION] bar";

  my $top = $root->get_package($root);
  is_can [$top, 'foo'], "FOO", "[$SESSION] top->foo";
  is_can [$top, 'bar'], "BAR", "[$SESSION] top->bar";
  is $top, "MyApp$SESSION", "[$SESSION] top == class app_prefix";
}

# [4]
{
  $SESSION++;
  my $DIR = $TMPDIR->
    ([DIR => 'app'
      , [FILE => '.htyattrc'
	 , q{use YATT::Registry base => 'normal'; sub foo {"FOO"}}]
      , [FILE => 'index.html', q{<!yatt:base "simple">}]
      , [DIR  => 'normal'
	 , [FILE => 'simple.html', q{<!yatt:widget foo><h2>simple</h2>}]]]);

  my $root = new YATT::Registry
    (loader => [DIR => "$DIR/app"]
     , app_prefix => "MyApp$SESSION"
     , auto_reload => 1);

  isnt my $index = $root->get_ns(['index']), undef, "[$SESSION] index";
  isa_ok $index, $root->Template, "[$SESSION] index";
  isnt $root->get_widget_from_template($index, qw(yatt foo)), undef
    , "[$SESSION] foo";
}

# [5]
{
  $SESSION++;
  my $DIR = $TMPDIR->
    ([DIR => 'app'
      , [FILE => '.htyattrc'
	 , q{use YATT::Registry base => 'normal'}]
      , [FILE => 'index.html', q{<h2>hello</h2>}]
      , [DIR  => 'normal'
	 , [DIR  => 'simple'
	    , [FILE => 'widget.html', q{<h2>simple</h2>}]]]]);

  my $root = new YATT::Registry
    (loader => [DIR => "$DIR/app"]
     , app_prefix => "MyApp$SESSION"
     , auto_reload => 1);

  isnt my $index = $root->get_ns(['index']), undef, "[$SESSION] index";
  isa_ok $index, $root->Template, "[$SESSION] index";
  isnt $root->get_widget_from_template
    ($index, qw(yatt simple widget)), undef, "[$SESSION] simple widget";
}
