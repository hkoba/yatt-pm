#!/usr/bin/perl -w
use strict;
use warnings;

my ($line, $context);
while (<>) {
  chomp;
  if (s/^(\#)?(AddHandler cgi-script \.cgi\b.*)$/$2/) {
    print STDERR $1 ? "Changed" : "Already OK", ": $2\n";
  } elsif ($line = m{^(<Directory "/var/www/cgi-bin">)} .. m{^</Directory}) {
    $context = $1 if $line == 1;
    ensure_config("Options", "ExecCGI", $context);
  } elsif ($line = m{^(<Directory "/var/www/html">)} .. m{^</Directory}) {
    $context = $1 if $line == 1;
    ensure_config("AllowOverride", "All", $context);
  }
} continue {
  print "$_\n";
}

sub ensure_config {
  my ($config, $expect, $context) = @_;
    my ($value) = /^\s*$config\b(.*)/
      or return;
    if ($value =~ /None/) {
      $value = $expect;
    } elsif ($value !~ /$expect/) {
      $value .= " $expect";
    } else {
      print STDERR "Already OK: $context $_\n";
      return;
    }
    $_ = "$config $value";
    print STDERR "Changed: $context $_\n";
}
