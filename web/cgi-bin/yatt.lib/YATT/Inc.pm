# -*- mode: perl; coding: utf-8 -*-
package YATT::Inc;
use strict;
use warnings FATAL => qw(all);

sub import {
  my ($callpack) = caller;
  $callpack =~ s{::}{/}g;
  $INC{$callpack . '.pm'} = 1;
}

1;
