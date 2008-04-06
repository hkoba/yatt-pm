package YATT::Class::Hierarchy;
use strict;
use warnings FATAL => qw(all);

use YATT::Fields ();
use YATT::Util::Symbol;

sub Base () { 'YATT::Class::Configurable' }

sub import {
  shift;
  my ($callpack) = caller;
  my $self = bless [$callpack], __PACKAGE__;
  my %opts;
  while (@_ >= 2 && !ref $_[0] && $_[0] =~ /^-/) {
    $opts{$_[0]} = $_[1];
    splice @_, 0, 2;
  }

  my $script;
  foreach my $desc (@_) {
    $script .= $self->make_class_hierarchy
      ($desc, $callpack . '::', $opts{-base} || $self->Base);
  }
  # export_ok も欲しいのでは?
  $script .= $self->make_class_aliases(do {
    if ($opts{-base}) {
      [Base => $opts{-base}]
    } else {
      ()
    }
  });
  print $script if $opts{-debug};
  eval $script;
  die $@ if $@;
}

sub make_class_aliases {
  my ($self) = shift;
  my $callpack = $self->[0];
  my $stash = *{globref($callpack, '')}{HASH};
  my $script = <<END;
package $callpack;
our \@EXPORT_OK = qw(@{[join "\n ", map {$$_[0]} @{$self}[1..$#$self]]});
END
  foreach my $classdef (@{$self}[1 .. $#$self], @_) {
    next if exists $stash->{$classdef->[0]};
    $script .= <<END;
sub $classdef->[0] () {'$classdef->[1]'}
END
  }
  $script;
}

sub make_class_hierarchy {
  my ($self, $desc, $prefix, $super) = @_;
  my ($class, $slots) = splice @$desc, 0, 2;
  push @$self, [$class, $prefix.$class];
  my $script = $self->make_class($prefix.$class, $super, @$slots);
  foreach my $child (@$desc) {
    $script .= $self->make_class_hierarchy($child, $prefix, $prefix.$class);
  }
  $script;
}

sub make_class {
  my ($self, $class, $super, @slots) = @_;
  <<END . ($super ? <<END : "") . (@slots ? <<END : "") . "\n";
package $class;
END
use base qw($super);
END
use YATT::Fields qw(@slots);
END
}

1;
