package YATT::Util::VarExporter;
use strict;
use warnings FATAL => qw(all);

use base qw(YATT::Class::Configurable);
use YATT::Fields qw(pages);

use YATT::Util::Symbol;

sub import {
  my $pack = shift;
  my $callpack = caller;
  my $self = $pack->new(@_);
  $self->register_into($callpack);
  # $callpack に cache を作り、かつ、 import を作る
}

sub new {
  my MY $self = shift->SUPER::new;
  while (my ($page, $vars) = splice @_, 0, 2) {
    $self->{pages}{$page} = $vars;
  }
  $self
}

sub register_into {
  (my MY $self, my $pkg) = @_;
  MY->add_isa($pkg, MY);
  *{globref($pkg, '_CACHE')} = \ $self;
  *{globref($pkg, 'find_vars')} = sub {
    shift->instance->find_vars(@_);
  };
  *{globref($pkg, 'import')} = sub {
    my $callpack = caller;
    my MY $self = shift->instance;
    $self->export_to($callpack, @_);
  };
}

sub instance {
  my ($mypkg) = @_;
  ${*{globref($mypkg, '_CACHE')}{SCALAR}};;
}

sub export_to {
  (my MY $self, my ($destpkg, $page, $failok)) = @_;
  my $vars = $self->find_vars($page ||= $self->page_name)
    or $failok or die "No such page: $page";

  foreach my $name (keys %$vars) {
    *{globref($destpkg, $name)} = do {
      my $ref = ref $vars->{$name};
      if (not $ref or $ref eq 'ARRAY' or $ref eq 'HASH') {
	\ $vars->{$name};
      } else {
	$vars->{$name}
      }
    };
  }
}

sub find_vars {
  my MY $self = ref $_[0] ? shift : shift->instance();
  my ($page, $varname) = @_;
  my $page_vars = $self->{pages}{$page}
    or return;
  unless (defined $varname) {
    $page_vars;
  } else {
    $page_vars->{$varname};
  }
}

# YATT 固有で良いよね。

sub build_scope_for {
  my ($mypkg, $gen, $page) = @_;
  my MY $self = $mypkg->instance;
  my $vars = $self->find_vars($page);
  my %scope;
  foreach my $name (keys %$vars) {
    my $value = $vars->{$name};
    unless (ref $value) {
      $scope{$name} = $gen->t_text->new(varname => $name);
    } elsif (ref $value eq 'ARRAY') {
      $scope{$name} = $gen->t_list->new(varname => $name);
    } else {
      $scope{$name} = $gen->t_scalar->new(varname => $name);
    }
  }
  \%scope;
}

1;
