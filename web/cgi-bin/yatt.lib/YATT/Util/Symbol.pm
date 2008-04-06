# -*- mode: perl; coding: utf-8 -*-
package YATT::Util::Symbol;
use base qw(Exporter);
use strict;
use warnings FATAL => qw(all);

BEGIN {
  our @EXPORT_OK = qw(class symtab globref globelem
		      glob_default glob_init findname
		      fields_hash fields_hash_of_class
		      gather_classvars
		      delete_package
		      pkg_exists pkg_ensure_main pkg_split
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

# Do not use this as method. Use as symtab($obj),
# or it will return your *base* class!
sub symtab {
  no strict 'refs';
  my $class = class($_[0]);
  $class =~ s/:*$/::/;
  *{$class}{HASH};
}

sub globref {
  my ($thing, $name) = @_;
  no strict 'refs';
  \*{class($thing) . "::$name"};
}

sub globelem {
  no strict 'refs';
  *{$_[0]}{$_[1]}
}

sub glob_default {
  no strict 'refs';
  my $type = ref $_[1];
  *{$_[0]}{$type} || do {
    *{*{$_[0]} = $_[1]}{$type}
  };
}

sub glob_init {
  my ($sym, $type, $sub) = @_;
  no strict 'refs';
  *{$sym}{$type} || do {
    *{*$sym = $sub->()}{$type}
  }
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

# stolen/modified from Attribute::Handlers
{
  my %symcache;
  sub findname {
    my ($pkg, $ref, $type) = @_;
    return $symcache{$pkg,$ref} if $symcache{$pkg,$ref};
    $type ||= ref $ref;
    my $symtab = symtab($pkg);
    foreach my $name (keys %$symtab) {
      my $sym = $symtab->{$name};
      return $symcache{$pkg,$ref} = $name
	if globelem($sym, $type) && globelem($sym, $type) == $ref;
    }
  }
}

sub gather_classvars {
  my ($baseClass, $leafClass, $arrayName) = @_;
  my $ary = *{globref($leafClass, $arrayName)}{ARRAY};
  my @result = ([$leafClass, $ary ? @$ary : ()]);
  if ($leafClass ne $baseClass) {
    my $isa = *{globref($leafClass, 'ISA')}{ARRAY};
    foreach my $super ($isa ? @$isa : ()) {
      next unless UNIVERSAL::isa($super, $baseClass);
      push @result, gather_classvars($baseClass, $super, $arrayName);
    }
  }
  @result;
}

#

sub pkg_exists {
  my ($stem, $leaf) = pkg_split(@_);
  my $stem_symtab = symtab($stem);
  defined $stem_symtab && exists $stem_symtab->{$leaf};
}

sub pkg_split {
  $_[0] =~ s{:*$}{::};
  my ($stem, $leaf) = $_[0] =~ m/(.*::)(\w+::)$/
    or die "Can't split package: $_[0]";
  ($stem, $leaf);
}

sub pkg_ensure_main {
  my ($pkg) = @_;
  unless ($pkg =~ /^main::.*::$/) {
    $pkg = "main$pkg"       if      $pkg =~ /^::/;
    $pkg = "main::$pkg"     unless  $pkg =~ /^main::/;
    $pkg .= '::'            unless  $pkg =~ /::$/;
  }
  $pkg;
}

# Stolen from Symbol.pm
sub delete_package ($;$) {
  my ($pkg, $debug) = (shift, numeric(shift));
  my ($stem, $leaf) = pkg_split($pkg);
  my $stem_symtab = symtab($stem);
  unless (defined $stem_symtab and exists $stem_symtab->{$leaf}) {
    print STDERR "package is already empty: $pkg \[$stem $leaf]\n" if $debug;
    return;
  }

  # free all the symbols in the package
  my $leaf_symtab = *{$stem_symtab->{$leaf}}{HASH};
  foreach my $name (keys %$leaf_symtab) {
    print STDERR "deleting $pkg$name\n" if $debug >= 2;
    my $sym = delete $leaf_symtab->{$name};
    next unless defined $sym and ref $sym eq 'GLOB'; # XXX: but why?
    undef *$sym;
  }

  # delete the symbol table
  %$leaf_symtab = ();
  delete $stem_symtab->{$leaf};
}

sub let_in {
  my ($pack, $obj, $binding) = splice @_, 0, 3;
  my ($k, $v) = splice @$binding, 0, 2;
  local *{globref($pack, $k)} = $v;
  if (@$binding) {
    let_in($pack, $obj, $binding, @_);
  } else {
    my ($method) = shift;
    $obj->$method(@_);
  }
}

sub add_isa {
  my ($pack, $targetClass, $baseClass) = @_;
  my $isa = globref($targetClass, 'ISA');
  if (my $array = *{$isa}{ARRAY}) {
    return if lsearch {$_ eq $baseClass} $array;
  } else {
    *{$isa} = [];
  }
  # XXX: 多重継承は？
  push @{*{$isa}{ARRAY}}, $baseClass;
}

sub lift_isa_to {
  my ($new_parent, $child) = @_;
  my $orig = *{globref($child, 'ISA')};
  my $isa = *{$orig}{ARRAY};
  *{$orig} = $isa = [] unless $isa;
  my @orig = @$isa;
  croak "Multiple inheritance is not supported: @orig" if @orig > 1;

  # !!: *{$orig} = [$new_parent]; is not ok.
  @$isa = $new_parent;

  return unless @orig;
  add_isa(undef, $new_parent, @orig);
}

1;
