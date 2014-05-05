# -*- mode: perl; coding: utf-8 -*-
package YATT::ArgTypes; use YATT::Inc;
use strict;
use warnings FATAL => qw(all);

use base qw(YATT::Class::Configurable);
use YATT::Fields qw(cf_callpack
		    cf_base cf_type_map cf_type_fmt
		    cf_type_name
		    cf_debug
		  );
use YATT::Util;
use YATT::Util::Symbol;
use Carp;
use mro ();

sub import {
  my $pack = shift;
  my ($callpack) = caller;
  my @types;
  my $opts = $pack->new(callpack => $callpack
			, $pack->parse_args(\@_, \@types));
  $opts->add_type($_) for @types;

  $opts->method_changed;
}

sub parse_args {
  my ($pack, $arglist, $taskqueue) = @_;
  my @confs;
  while (@$arglist) {
    if (ref $arglist->[0]) {
      push @$taskqueue, shift @$arglist;
    } elsif (my ($flag, $key) = $arglist->[0] =~ /^([\-:])(\w+)/) {
      shift @$arglist;
      my $value = $flag eq ':' ? 1 : shift @$arglist;
      push @confs, $key, $value;
    } else {
      croak "Invalid option '$arglist->[0]'";
    }
  }
  @confs;
}

sub add_type {
  (my MY $self, my ($desc)) = @_;
  my $type = shift @$desc;
  my $fullclass = sprintf $self->{cf_type_fmt}, $type;

  $self->{cf_type_map}{$type} = $fullclass;

  *{globref($fullclass, "type_name")} = sub () { $type }
  if $self->{cf_type_name};

  # t_zzz typealias.
  $self->add_constant("t_$type", $fullclass);

  my $fields = fields_hash($self);

  my (@symbols, @tasks, %config);
  while (@$desc) {
    if (ref $desc->[0] eq 'SCALAR') {
      my ($nameref, $value) = splice @$desc, 0, 2;
      my $code = do {
	unless (ref $value) {
	  sub () { $value };
	} elsif (ref $value eq 'CODE') {
	  $value;
	} else {
	  die "Unknown ArgType desc for $$nameref : '$value'";
	}
      };
      push @symbols, [$$nameref, $code];
      # *{globref($fullclass, $$nameref)} = $code;
    } elsif (my ($flag, $key) = $desc->[0] =~ /^([\-:])(\w+)/) {
      shift @$desc;
      my $value = $flag eq ':' ? 1 : shift @$desc;
      if ($fields->{"cf_$key"}) {
	$config{"cf_$key"} = $value;
      } else {
	my $sub = $self->can("option_$key")
	  or die "Unknown ArgType option $key";
	push @tasks, [$sub, $value];
      }
      # $sub->($self, $fullclass, $value);
    } else {
      die "Unknown desc type $desc"
    }
  }

  # base だけは eval を使う。 さもないと %FIELDS が作られない。
  # *{globref($fullclass, 'ISA')} = [$self->{cf_base}];
  $self->checked_eval
    (sprintf qq{package %s; use base qw(%s)}
     , $fullclass
     , $self->lookup_in($self->{cf_type_map}, $config{cf_base})
     || $$self{cf_base});

  foreach my $rec (@symbols) {
    my ($sym, $code) = @$rec;
    *{globref($fullclass, $sym)} = $code;
  }

  foreach my $rec (@tasks) {
    my ($sub, $value) = @$rec;
    $sub->($self, $fullclass, $value, \%config);
  }
}

sub add_constant {
  (my MY $self, my ($name, $value)) = @_;
  my $symbol = globref($self->{cf_callpack}, $name);
  if ($] >= 5.019003) {
    Internals::SvREADONLY($value, 1);
    my $symtab_glob = globref($self->{cf_callpack}, "");
    my $symtab = *{$symtab_glob}{HASH};
    if ($symtab and not exists $symtab->{$name}) {
      $symtab->{$name} = \ $value;
    } else {
      my $ourSymtab = *{globref(__PACKAGE__, "")}{HASH};
      local $ourSymtab->{_dummy} = \ $value;
      *$symbol = do {no strict 'refs'; \&{"_dummy"}};
      # *$symbol = *{$ourSymtab->{_dummy}}{CODE};
    }
  }  else {
    *$symbol = sub () { $value }
  }
}

sub method_changed {
  (my MY $self) = @_;
  mro::method_changed_in($self->{cf_callpack});
}

sub lookup_in {
  my ($self, $hash, $key) = @_;
  return unless defined $key;
  $hash->{$key};
}

sub option_alias {
  (my MY $self, my ($class, $value)) = @_;
  foreach my $alias (ref $value ? @$value : $value) {
    $self->{cf_type_map}{$alias} = $class;
  }
}

sub option_fields {
  (my MY $self, my ($class, $value)) = @_;
  my $fields = terse_dump(@$value);
  $self->checked_eval(<<END);
package $class; use YATT::Fields $fields;
END
}

1;
