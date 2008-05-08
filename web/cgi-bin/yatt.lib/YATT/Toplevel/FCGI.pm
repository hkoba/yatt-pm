# -*- mode: perl; coding: utf-8 -*-
package YATT::Toplevel::FCGI;
use strict;
use warnings FATAL => qw(all);

use Exporter qw(import);

use base qw(YATT::Toplevel::CGI);
use YATT::Toplevel::CGI;

use FCGI;
use YATT::Util;

#========================================

sub run {
  my ($pack) = shift;
  my $age = -M $0;
  my $request = FCGI::Request();
  while ($request->Accept >= 0) {
    catch {
      $pack->SUPER::run('cgi');
    };
    if (-M $0 < $age) {
      FCGI::Finish($request);
      last;
    }
  }
}

1;
