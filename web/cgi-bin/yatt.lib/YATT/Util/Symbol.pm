# -*- mode: perl; coding: utf-8 -*-
package YATT::Util::Symbol;
use base qw(Exporter);
use strict;
use warnings FATAL => qw(all);

BEGIN {
  our @EXPORT_OK = qw(class globref
		      fields_hash fields_hash_of_class
		      add_isa lift_isa_to
		      declare_alias
		    );
  our @EXPORT    = @EXPORT_OK;
}

use Carp;
use YATT::Util qw(numeric lsearch);

sub class {
  ref $_[0] || $_[0]
}

sub globref {
  my ($thing, $name) = @_;
  no strict 'refs';
  \*{class($thing) . "::$name"};
}

sub declare_alias ($$) {
  my ($name, $sub, $pack) = @_;
  $pack ||= caller;
  *{globref($pack, $name)} = $sub;
}

sub fields_hash_of_class {
  *{globref($_[0], 'FIELDS')}{HASH};
}

*fields_hash = do {
  if ($] >= 5.009) {
    \&fields_hash_of_class;
  } else {
    sub { $_[0]->[0] }
  }
};

sub add_isa {
  my ($pack, $targetClass, @baseClass) = @_;
  my $isa = globref($targetClass, 'ISA');
  my @uniqBase;
  if (my $array = *{$isa}{ARRAY}) {
    foreach my $baseClass (@baseClass) {
      next if $targetClass eq $baseClass;
      next if lsearch {$_ eq $baseClass} $array;
      push @uniqBase, $baseClass;
    }
  } else {
    *{$isa} = [];
    @uniqBase = @baseClass;
  }
  push @{*{$isa}{ARRAY}}, @uniqBase;
}

sub lift_isa_to {
  my ($new_parent, $child) = @_;
  my $orig = *{globref($child, 'ISA')};
  my $isa = *{$orig}{ARRAY};
  *{$orig} = $isa = [] unless $isa;
  my @orig = @$isa;
#  croak "Multiple inheritance is not supported: $child isa @orig"
#    if @orig > 1;

  # !!: *{$orig} = [$new_parent]; is not ok.
  @$isa = $new_parent;

  return unless @orig;
  add_isa(undef, $new_parent, @orig);
}

1;
