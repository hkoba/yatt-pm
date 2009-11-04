#!/usr/bin/perl -w
use strict;
use warnings FATAL => qw(all);

use FindBin;
use lib "$FindBin::Bin/..";

use Test::More;

unless (eval {require BSD::Resource}) {
  plan skip_all => 'BSD::Resource is not installed'; exit;
}

plan tests => 3;

ok(chdir "$FindBin::Bin/..", 'chdir to lib dir');

require_ok('YATT::Util::RLimit');

my $script = q{rlimit_vmem(200) or die $@; eval q{print "p03" .. "p05_1"}};

like qx($^X -I. -MYATT::Util::RLimit -e '$script' 2>&1), qr{^Out of memory}
  , "Memory hog should be detected.";
