#!/usr/bin/perl -w
# -*- mode: perl; coding: utf-8 -*-
use strict;
use warnings qw(FATAL all NONFATAL misc);
use FindBin;
use lib "$FindBin::Bin/../..";

use Test::More;

use parent 'YATT::Toplevel::CGI';
use YATT::Translator::Perl ();
sub MY () {__PACKAGE__}
# INC{'main.pm'}  is required because our toplevel is main
# and is used like "require $trans->{cf_default_base_class}".
BEGIN {$INC{'main.pm'} = 1;}

use YATT::Util qw/catch/;
use YATT::Exception qw(Exception);

{
  # abspath is important.
  my $docroot = MY->rel2abs(rootname($0).".d");

  chdir($docroot)
    or Carp::croak "Can't chdir to $docroot: $!";

  my $top = MY->new_translator([DIR => $docroot]
			       , MY->new_config->translator_param
			       , mode => 'render');

  my @wpath = MY->widget_path_in($docroot, MY->rel2abs('index'));

  if (my $widget = $top->get_widget(@wpath)) {
    my Exception $error;
    my $rc = catch {
      $top->ensure_widget_is_generated($widget);
    } \$error;

    isnt $rc, '', "Error should be raised";

    like $error
      , qr{^No such widget \(<yatt:dirx:foo:barrr />\), at file \S+ line 1\n$}
      , "Error diag shoud report root of cause";

  } else {
    BAILOUT("Can't find testee widget");
  }
}

done_testing();

sub rootname {
  my ($fn) = @_;
  $fn =~ s/\.[^\.]+$//;
  $fn;
}
