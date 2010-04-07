#!/usr/bin/perl -w
# -*- mode: perl; coding: utf-8 -*-
use strict;
use warnings FATAL => qw(all);
use Test::More qw(no_plan);
use Test::Differences;

use FindBin;
use lib "$FindBin::Bin/..";

sub dumper {
  Data::Dumper->new(\@_)->Terse(1)->Indent(0)->Dump;
}

my $CLS = 'YATT::DBSchema';
my $MEMDB = ':memory:';
require_ok($CLS);

# use 抜きの、素の YATT::DBSchema->create を試す。

{
  my $schema = $CLS->create
    ([foo => []
      , [id => 'integer', -auto_increment, -primary_key]
      , [foo => 'text', -indexed]
      , [bar_id => [bar => []
		    , [bar_id => 'integer', -auto_increment, -primary_key]
		    , [bar => 'text', -unique]]]
      , [baz => 'text']]);

  $schema->connect_via_sqlite($MEMDB, 'w');

  my $ins = $schema->to_insert(foo => qw(foo bar_id baz));
  $ins->('FOO', 'bar', 'BAZ');
  $ins->('foo', 'bar', 'baz');
  $ins->('Foo', 'BAR', 'baz');

  is_deeply $schema->dbh->selectall_arrayref(<<END)
select foo, bar, baz from foo left join bar using(bar_id)
END
    , [['FOO', 'bar', 'BAZ']
       , ['foo', 'bar', 'baz']
       , ['Foo', 'BAR', 'baz']], 'inserted.';

  is_deeply $schema->to_select
    (foo => {where => {bar => 'BAR'}, columns => [qw(foo bar baz)]})
      ->fetchall_arrayref
	, [['Foo', 'BAR', 'baz']]
	  , 'to_select where {bar => "BAR"}';

  $schema->dbh->commit;
}
