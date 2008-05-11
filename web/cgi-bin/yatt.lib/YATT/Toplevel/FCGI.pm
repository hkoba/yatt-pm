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
  my ($pack, $request) = splice @_, 0, 2;
  my $config = $pack->new_config(@_);
  my $age = -M $0;
  $request = FCGI::Request() unless defined $request;
  while ($request->Accept >= 0) {
    catch {
      $pack->SUPER::run('cgi', undef, $config);
    };
    $request->Finish;
    last if -e $0 and -M $0 < $age;
  }
}

1;
