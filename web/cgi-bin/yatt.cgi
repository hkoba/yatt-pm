#!/usr/bin/perl -Tw
use 5.006;
use strict;
use warnings FATAL => 'all';

#----------------------------------------
# Path setup.

use File::Basename; # require is not ok for fileparse.
use File::Spec; # require is not ok for rel2abs

# pathname without extension.
sub rootname {
  my ($basename, $dirname, $suffix) = fileparse(@_);
  join "/", File::Spec->rel2abs($dirname), $basename;
}

sub untaint_anything {
  $1 if defined $_[0] && $_[0] =~ m{(.*)}s;
}

sub catch (&@) {
  my ($sub, $errorVar) = @_;
  eval { $sub->() };
  $$errorVar = $@;
}

sub breakpoint {}

use lib map {-d $_ ? untaint_anything($_) : ()}
  rootname(__FILE__, qr{\.(f?cgi|pl)}) . ".lib";

use YATT;

#----------------------------------------
if ($0 =~ /\.fcgi$/) {
  my $age = -M $0;
  my $load_error;
  if (catch {require CGI::Fast} \$load_error) {
    print "\n\n$load_error";
    while (sleep 3) {
      last if -M $0 < $age;
    }
    exit 1;
  }
  elsif (catch {require YATT::Toplevel::FCGI} \$load_error) {
    # To avoid "massive (reload -> reload) ==> restartDelay" blocking.
    while (new CGI::Fast) {
      print "\n\n$load_error";
      last if -M $0 < $age;
    }
    exit 1;
  }
  else {
    YATT::Toplevel::FCGI->run;
  }
}
elsif ($ENV{LOCAL_COOKIE}) {
  # For w3m
}
else {
  # For normal CGI
  my $class = 'YATT::Toplevel::CGI';
  if ($ENV{SERVER_SOFTWARE}) {
    eval "require $class";
    if (my $load_error = $@) {
      print "\n\n$load_error";
      exit 1;
    }
    else {
      breakpoint;
      $class->run(cgi => @ARGV);
    }
  }
  else {
    my $sub = eval qq{sub {require $class}};
    $sub->();
    $class->run(template => @ARGV);
  }
}
