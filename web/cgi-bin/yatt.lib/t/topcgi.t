#!/usr/bin/perl -w
# -*- mode: perl; coding: utf-8 -*-
use strict;
use warnings FATAL => qw(all);
use strict;
use warnings FATAL => qw(all);
use FindBin;
use lib "$FindBin::Bin/..";
use YATT::Test qw(no_plan);
use File::Temp qw/tempdir/;

use File::stat;

require_ok(my $class = 'YATT::Toplevel::CGI');
&YATT::break_translator;

my $TMPDIR = tmpbuilder(tempdir(CLEANUP => 0));

my $SESSION = 1;
{
  my $DIR = $TMPDIR->([DIR => 'foo'
		       , [FILE => 'bar.html'
			  , my $BAR = q{<h2>bar.html</h2>}]],
		      );

  my ($instpkg, $trans, $config)
    = $class->create_toplevel($DIR, auto_reload => 1
			      , find_root_upward => 0);
  isnt $instpkg, '', 'instpkg';
  isnt $instpkg->can('dispatch'), '', 'instpkg->can dispatch';
  isnt $trans, '', 'trans';
  isnt $trans->can('lookup_handler_to'), '', 'trans->can lookup_handler_to';
  isnt $config, '', 'config';
  isnt $config->can('configure'), '', 'config->can configure';

  is_rendered [$trans, [qw(foo bar)]], $BAR, 'foo:bar';
}
