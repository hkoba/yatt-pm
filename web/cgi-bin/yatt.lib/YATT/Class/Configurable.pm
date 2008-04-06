# -*- mode: perl; coding: utf-8 -*-
package YATT::Class::Configurable;
use strict;
use warnings FATAL => qw(all);
use fields;
sub MY () {__PACKAGE__}
use YATT::Util::Symbol qw(fields_hash);
use Carp;

sub new {
  my MY $self = fields::new(shift);
  $self->before_configure;
  if (@_) {
    $self->init(@_);
  } else {
    $self->after_configure;
  }
  $self
}

sub initargs {return}

sub init {
  my MY $self = shift;
  if (my @member = $self->initargs) {
    @{$self}{@member} = splice @_, 0, scalar @member;
  }
  if (@_) {
    $self->configure(@_);
  } else {
    $self->after_configure;
  }
  $self;
}

sub stringify {
  my MY $self = shift;
  require Data::Dumper;
  sprintf '%s->new(%s)', ref $self
    , join ", ", Data::Dumper->new
      ([map($self->{$_}, $self->initargs)
	, $self->configure])->Terse(1)->Indent(0)->Dump;
}

sub clone {
  my MY $ref = shift;
  ref($ref)->new(map($ref->{$_}, $ref->initargs)
		 , $ref->configure
		 , @_);
}

sub cget {
  (my MY $self, my ($cf)) = @_;
  my $fields = fields_hash($self);
  croak "Can't cget $cf" unless exists $fields->{"cf_$cf"};
  $self->{"cf_$cf"};
}

sub cgetlist {
  (my MY $self) = shift;
  map {
    if (exists $self->{"cf_$_"}) {
      ($_ => $self->{"cf_$_"})
    } else {
      ()
    }
  } @_;
}


sub before_configure {}

sub configkeys {
  my MY $self = shift;
  return map {
    if (m/^cf_(.*)/) {
      $1
    } else {
      ()
    }
  } keys %$self;
}

sub configure {
  my MY $self = shift;
  my $fields = fields_hash($self);
  unless (@_) {
    # list all configurable options.
    return map {
      if (m/^cf_(.*)/) {
	($1 => $self->{$_})
      } else {
	()
      }
    } keys %$fields;
  }
  if (@_ == 1) {
    croak "No such config item: $_[0]" unless exists $fields->{"cf_$_[0]"};
    return $self->{"cf_$_[0]"};
  }
  if (@_ % 2) {
    croak "Odd number of arguments";
  }

  my @task;
  while (my ($name, $value) = splice @_, 0, 2) {
    if (my $sub = $self->can("configure_$name")) {
      push @task, [$sub, $value];
    } else {
      croak "No such config item: $name" unless exists $fields->{"cf_$name"};
      $self->{"cf_$name"} = $value;
    }
  }
  foreach my $task (@task) {
    $task->[0]->($self, $task->[1]);
  }
  $self->after_configure;
  $self;
}

sub after_configure {
  my MY $self = shift;
  # $self->SUPER::after_configure;
  foreach my $cf (grep {/^cf_/} keys %{fields_hash($self)}) {
    next if defined $self->{$cf};
    my $sub = $self->can("default_$cf") or next;
    $self->{$cf} = $sub->();
  }
}
1;
