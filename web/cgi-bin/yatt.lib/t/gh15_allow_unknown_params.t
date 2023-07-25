#!/usr/bin/perl -w
# -*- mode: perl; coding: utf-8 -*-
use strict;
use warnings qw(FATAL all NONFATAL misc);
use FindBin;
use lib "$FindBin::Bin/..";
use Test::More;

use Test::WWW::Mechanize::CGI;
use CGI;
use YATT::Toplevel::CGI;

# ↓This is important to set $SCRIPT_FILENAME correctly.
$0 = File::Spec->rel2abs(__FILE__);

{
  my $mech = oneshot_mech_for_cgi();

  $mech->get_ok('http://localhost/test.html?foo=xxx&bar=yyy'
                , "sanity check");
  $mech->text_contains("foo=(xxx)");
}

{
  my $mech = oneshot_mech_for_cgi();

  $mech->get_ok('http://localhost/test.html?foo=bar&unknown=aaa'
                , "unknown parameter should not raise an error");
  $mech->text_contains("foo=(bar)");
}

done_testing;

sub oneshot_mech_for_cgi {
  # local $ENV{DOCUMENT_ROOT} = File::Basename::dirname($0);

  my $mech = Test::WWW::Mechanize::CGI->new;
  $mech->cgi(sub {
    YATT::Toplevel::CGI->run(cgi => ());
  });

  return $mech;
}
