#!/usr/bin/perl -w
# -*- mode: perl; coding: utf-8 -*-
use strict;
use warnings qw(FATAL all NONFATAL misc);
use FindBin;
use lib "$FindBin::Bin/..";
use YATT::Test;

# Note: This test relies actual vmem size of perl5 and yatt,
# so this may fail for perl versions and/or OS releases.

use File::stat;

#----------------------------------------
my $SCRIPT = "$FindBin::Bin/../../../../scripts/yatt.render";

unless (-x $SCRIPT) {
  plan skip_all => "yatt.render is missing"; exit
}

if (do {eval {require BSD::Resource}; $@}) {
  plan skip_all => "BSD::Resource is required to test rlimit."; exit
}

my $tester = sub {
  my $out = qx($^X -I$FindBin::Bin/../ $SCRIPT @_ 2>&1);
  chomp($out);
  $out
};

my $limit_meg = 100 + do {
  my $locale_archive = '/usr/lib/locale/locale-archive';
  if (-e $locale_archive) {
    int(stat($locale_archive)->size / (1024 * 1024));
  } else {
    0;
  }
};

#----------------------------------------
plan 'no_plan';

my $TMPDIR = tmpbuilder(rootname($0) . ".tmp");

{
  my $DIR = $TMPDIR->([FILE => 'bar.html'
		       , my $BAR = q{<h2>bar.html</h2>}]
		      , [FILE => '.htyattroot', <<"END"]
rlimit{
vmem: $limit_meg
}
END
		      , [FILE => 'baz.html'
			 , q{<?perl= "p03" .. "p05_1"?>}]
		      );

  is $tester->("$DIR/bar.html"), $BAR, "yatt.render: normal";
  like $tester->("$DIR/baz.html"), qr{^Out of memory}
    , "yatt.render should die with 'Out of memory!' when rlimit.vmem=$limit_meg";
}
