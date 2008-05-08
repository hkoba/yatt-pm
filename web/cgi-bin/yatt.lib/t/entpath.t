#!/usr/bin/perl -w
# -*- mode: perl; coding: utf-8 -*-
use strict;
use warnings FATAL => qw(all);
use FindBin;
use lib "$FindBin::Bin/..";

#========================================
use YATT::Test qw(no_plan);

#========================================
my $TRANS = 'YATT::LRXML::EntityPath';
require_ok($TRANS);

sub is_entpath {
  my ($in, $expect, $title) = @_;
  if ($title) {
    $title .= " $in" if defined $in;
  } else {
    $title = $in;
  }
  my @entpath = eval {$TRANS->parse_entpath($in)};
  if ($@) {
    Test::More::fail "$in\n $@";
  } else {
    is(dumper(@entpath)
       , dumper(defined $expect ? @$expect : $expect)
       , $title);
  }
}

{
  my ($test, $in) = ("parse_entpath");
  is_entpath undef, undef, "$test undef";

  is_entpath q{:foo}
    , [[var => 'foo']];

  is_entpath q{:foo:bar}
    , [[var => 'foo'], [var => 'bar']];

  is_entpath q{:foo:bar()}
    , [[var => 'foo'], [call => 'bar']];

  is_entpath q{:foo:bar():baz}
    , [[var => 'foo'], [call => 'bar'], [var => 'baz']];

  is_entpath q{:foo()}
    , [[call => foo =>]];

  is_entpath q{:foo(,)}
    , [[call => foo => [text => '']]];

  is_entpath q{:foo(,,)}
    , [[call => foo => [text => ''], [text => '']]];

  is_entpath q{:foo(bar)}
    , [[call => foo => [text => 'bar']]];

  is_entpath q{:foo(bar,)}
    , [[call => foo => [text => 'bar']]];

  is_entpath q{:foo(bar,,)}
    , [[call => foo => [text => 'bar'], [text => '']]];

  is_entpath q{:foo():bar()}
    , [[call => foo =>], [call => bar =>]];

  is_entpath q{:foo(bar,:baz(),,)}
    , [[call => foo => [text => 'bar'], [call => 'baz']
       , [text => '']]];

  is_entpath q{:yaml(config):title}
    , [[call => yaml => [text => 'config']]
       , [var  => 'title']
      ];

  is_entpath q{:foo[3][8]}
    , [[var => 'foo'], [aref => [expr => '3']], [aref => [expr => '8']]];

  is_entpath q{:schema:resultset(Artist):all()}
    , [[var => 'schema']
       , [call => resultset => [text => 'Artist']]
       , [call => 'all']];

  is_entpath q{:schema:resultset(Artist):search({name:{like:John%}})}
    , [[var => 'schema']
       , [call => resultset => [text => 'Artist']]
       , [call => 'search'
	  , [hash => [text => 'name']
	     , [hash => [text => 'like']
		, [text => 'John%']]]]
	 ];

  is_entpath q{:john_rs:search_related(cds):all()}
    , [[var => 'john_rs']
       , [call => search_related => [text => 'cds']]
       , [call => 'all']];

  is_entpath q{:first_john:cds(=undef,{order_by:title})}
    , [[var => 'first_john']
       , [call => 'cds'
	  , [expr => 'undef']
	  , [hash => [text => 'order_by']
	     , [text => 'title']]]];

  is_entpath q{:schema:resultset(CD):search({year:2000},{prefetch:artist})}
    , [[var => 'schema']
       , [call => resultset => [text => 'CD']]
       , [call => 'search'
	  , [hash => [text => 'year'], [text => '2000']]
	  , [hash => [text => 'prefetch'], [text => 'artist']]]];

  is_entpath q{:cd:artist():name()}
    , [[var => 'cd']
       , [call => 'artist']
       , [call => 'name']];

  is_entpath q{:foo(bar):baz():bang}
    , [[call => foo => [text => 'bar']]
       , [call => 'baz']
       , [var  => 'bang']
      ];

  is_entpath q{:foo(:bar:baz(:bang()),hoe,:moe)}
    , [[call => 'foo'
	, [[var => 'bar'], [call => 'baz', [call => 'bang']]]
	, [text => 'hoe']
	, [var  => 'moe']]];

  is_entpath q{:foo(bar(,)baz(),bang)}
    , [[call => 'foo'
	, [text => 'bar(,)baz()']
	, [text => 'bang']]];


  is_entpath q{:foo(=$i*($j+$k),,=$x[8]{y}:z):hoe}
    , [[call => 'foo'
	, [expr => '$i*($j+$k)']
	, [text => '']
	, [expr => '$x[8]{y}:z']]
      , [var => 'hoe']];

}
