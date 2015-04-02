package YATT::Util::CGICompat;
use strict;
use warnings FATAL => qw/all/;

use YATT::Util::Symbol qw/globref stash/;

use CGI;

sub import {
  unless (stash('CGI')->{'multi_param'}) {
    *{globref('CGI', 'multi_param')} = sub {
      shift->param(@_);
    };
  }
}

1;
