#!/usr/bin/perl -w
# -*- mode: perl; coding: utf-8 -*-
use strict;
use warnings FATAL => qw(all);
use Test::More qw(no_plan);
use Test::Differences;

use FindBin;
use lib "$FindBin::Bin/..";

use YATT::Util::Finalizer;

my $CLS = 'YATT::DBSchema';
my $MEMDB = ':memory:';
require_ok($CLS);

sub raises (&@) {
  my ($test, $errPat, $title) = @_;
  eval {$test->()};
  Test::More::like $@, $errPat, $title;
}

sub trim ($) {my $text = shift; $text =~ s/\n\Z//; $text}

# use 抜きの、素の YATT::DBSchema->create を試す。

{
  my $schema = $CLS->create
    ($ENV{DEBUG} ? (-verbose) : ()
     , [foo => []
      , [foo => 'text', -indexed]
      , [bar_id => [bar => []
		    , [bar_id => 'integer', -primary_key]
		    , [bar => 'text', -unique]]]
      , [baz => 'text']]);

  # XXX: SQLite 以外の create も吐けてほしい。
  eq_or_diff scalar $schema->sql_create, trim <<END, "sql_create";
CREATE TABLE foo
(foo text
, bar_id int
, baz text);
CREATE INDEX foo_foo on foo(foo);
CREATE TABLE bar
(bar_id integer primary key
, bar text unique)
END

  eq_or_diff scalar $schema->sql(qw(insert foo)), <<END, "sql insert foo";
INSERT INTO foo(foo, bar_id, baz)
values(?, ?, ?)
END
  eq_or_diff scalar $schema->sql(qw(select foo)), trim <<END, "sql select foo";
SELECT foo, foo.bar_id, bar_id.bar, baz FROM foo
LEFT JOIN bar bar_id on foo.bar_id = bar_id.bar_id
END
  eq_or_diff scalar $schema->sql(qw(update bar bar))
    , trim <<END, "sql update bar bar";
UPDATE bar SET bar = ? WHERE bar_id = ?
END

  #========================================

  raises {$schema->connect_to(foo => 'bar')}
    qr{^YATT::DBSchema: Unknown connection type: foo}
      , "Unknown connection type";


  $schema->connect_to(sqlite => $MEMDB, 'w');

  my $ins = $schema->to_insert('foo');
  $ins->('FOOx', 'bar', 'BAZ');
  $ins->('fooy', 'bar', 'baz');
  $ins->('Fooz', 'BAR', 'baz');

  is_deeply $schema->dbh->selectall_arrayref(<<END)
select foo, bar, baz from foo left join bar using(bar_id)
END
    , [['FOOx', 'bar', 'BAZ']
       , ['fooy', 'bar', 'baz']
       , ['Fooz', 'BAR', 'baz']], 'inserted.';

  is_deeply $schema->prepare_select
    (foo => [qw(foo bar baz)]
     , where => {bar => 'BAR'})->fetchall_arrayref
       , [['Fooz', 'BAR', 'baz']]
	 , 'prepare_select where {bar => "BAR"}';

  is_deeply $schema->select
    (foo => [qw(foo bar baz)]
     , hashref => 1, limit => 1, order_by => 'foo.rowid desc')
      , {foo => 'Fooz', bar => 'BAR', baz => 'baz'}
        , 'select hashref {}';

  is_deeply $schema->select
    (foo => [qw(foo bar baz)]
     , arrayref => 1, limit => 1, order_by => 'foo.rowid desc')
      , ['Fooz', 'BAR', 'baz']
        , 'select arrayref []';

  $schema->dbh->commit;
}

# import and run

{
  {
    package dbsch_test;
    $CLS->import(connection_spec => [sqlite => ':memory:', 'w']
		 , [foo => []
		    , [foo => 'text', -indexed]
		    , [bar_id => [bar => []
				  , [bar_id => 'integer', -primary_key]
				  , [bar => 'text', -unique]]]
		    , [baz => 'text']]);
  }
  raises {dbsch_test->run} qr{^Usage: dbsch.t method args..}, "run help";
  eq_or_diff capture {dbsch_test->run(select => 'foo')}, <<END, "run select";
foo\tbar_id\tbar\tbaz
END

  eq_or_diff capture {
    dbsch_test->run(sql => select => 'foo')
  }, <<END, "run sql select";
SELECT foo, foo.bar_id, bar_id.bar, baz FROM foo
LEFT JOIN bar bar_id on foo.bar_id = bar_id.bar_id
END
}

{
  my $tz = 3600*(localtime 0)[2];
  is $CLS->ymd_hms(0 - $tz), '1970-01-01 00:00:00', 'ymd_hms localtime';
  is $CLS->ymd_hms(0, 1), '1970-01-01 00:00:00', 'ymd_hms utc';
}
