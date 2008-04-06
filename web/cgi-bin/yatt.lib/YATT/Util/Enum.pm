# -*- mode: perl; coding: utf-8 -*-
package YATT::Util::Enum;
use strict;
use warnings FATAL => qw(all);

sub import {
  my ($pack) = shift;
  my $callpack = caller;

  #----------------------------------------
  my %opts;
  for (; @_ and $_[0] =~ /^-(\w+)/; splice @_, 0, 2) {
    $opts{$1} = $_[1];
  }
  my $offset = delete $opts{offset} || 0;
  my $prefix = delete $opts{prefix} || "";
  my $export = delete $opts{export}
    ? $callpack . "::EXPORT" : "";
  my $export_ok = $export || delete $opts{export_ok}
    ? $callpack . "::EXPORT_OK" : "";
  die "Unknown options for " . __PACKAGE__ . "\n".
    join ", ", keys %opts if keys %opts;

  #----------------------------------------
  foreach my $item (@_) {
    my $full_name = $callpack . "::" . $prefix . $item;
    {
      no strict 'refs';
      *$full_name = sub () { $offset };
      push @{$export}, $full_name if $export;
      push @{$export_ok}, $full_name if $export_ok;
    }
  } continue {
    $offset++;
  }
}

1;
