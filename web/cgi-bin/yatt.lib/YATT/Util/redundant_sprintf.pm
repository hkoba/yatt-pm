package YATT::Util::redundant_sprintf;
use strict;
use warnings FATAL => qw/all/;

sub import {
  warnings->unimport(qw/redundant/) if $] >= 5.021002;
}

1;
