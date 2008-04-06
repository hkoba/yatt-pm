# -*- mode: perl; coding: utf-8 -*-
package YATT::ArgMacro; use YATT::Inc;
use strict;
use warnings FATAL => qw(all);
use base qw(YATT::Class::Configurable);
use Data::Dumper;
use YATT::Util::Symbol qw(globref fields_hash_of_class);
use YATT::LRXML::Node qw(copy_array);
use Carp;

sub import {
  my ($pack, $macro_name, @fields) = @_;
  my %types;
  foreach my $slot (@fields) {
    my ($out) = $slot =~ /^out_(\w+)/ or next;
    my $type = $slot =~ s/^(\w+)=(.*)/$1/ ? $2 : 'text';
    $types{$out} = $type;
  }

  my ($callpack) = caller;
  my $class_name = "${callpack}::ArgMacro_$macro_name";
  my $fields = join ","
    , map {Data::Dumper->new([$_])->Terse(1)->Indent(0)->Dump} @fields;
  my $script = <<END;
package $class_name;
use strict;
use base qw(YATT::ArgMacro);
use YATT::Fields $fields;

sub $class_name () {'$class_name'}
END

  # print STDERR $script;
  eval $script;
  die $@ if $@;

  *{sym_out_atts($class_name)} = \%types;
}

sub sym_out_atts {
  globref(shift(), 'out_atts');
}

sub register_in {
  my ($pack, $registry, $macro_spec, $widget, %opts) = @_;

  my $fields = fields_hash_of_class($pack);

  {
    my ($dict, $order) = @$macro_spec;
    push @$order, $pack;

    foreach my $key (keys %$fields) {
      if (my ($name) = $key =~ /^cf_(\w+)/) {
	croak "ArgMacro $pack conflicts with $dict->{$name}"
	  if $dict->{$name};
	$dict->{$name} = [$pack, $name];
      }
    }
  }

  {
    my $types = *{sym_out_atts($pack)}{HASH};

    foreach my $key (keys %$fields) {
      if (my ($name) = $key =~ /^out_(\w+)/) {
	$widget->add_arg($name => $registry->create_var
			 ($types->{$name}, undef, varname => $name));
      }
    }
  }
}

sub create_from {
  my ($pack, $trans, $scope, $orig, $alias) = @_;
  my $fields = fields_hash_of_class($pack);
  my $copy = $orig->variant_builder;
  my ($name, $is_alias, @config);
  for (my $n = $orig->clone; $n->readable; $n->next) {
    unless ($n->is_attribute and $name = $n->node_name
	    and ($fields->{"cf_$name"}
		 || ($is_alias = $alias && $alias->{$name}))) {
      $copy->add_node(copy_array($n->current));
      next;
    }
    push @config, $is_alias ? $alias->{$name} : $name
      , $n->current;
  }
  if (@config) {
    my $macro = $pack->new(@config);
    $macro->accept($trans, $scope, $copy); # To avoid return value confusion.
    ($macro, $copy)
  } else {
    (undef, $orig);
  }
}

sub handle {
  my ($macro, $trans, $scope, $node) = @_;
  $macro->accept($trans, $scope, $node);
  $node;
}

sub expand_all_macros {
  my ($pack, $trans, $scope, $node, $hook, $order) = @_;
  my $copy = $node->variant_builder;
  $copy->add_filtered_copy($node->clone, [\&filter, $hook, \ my %found]);
  if (%found) {
    foreach my $type (@$order) {
      my $macro = $found{$type} or next;
      $copy = $macro->handle($trans, $scope, $copy);
    }
    $copy;
  } else {
    $node;
  }
}

sub filter {
  my ($hook, $unique, $name, $value) = @_;
  if (my $desc = $hook->{$name}) {
    my ($type, $opt) = @$desc;
    my $macro = $unique->{$type} ||= $type->new;
    # text になってないと、不便では?
    # ← でも、<:att>....</:att> の場合も有る。
    $macro->configure($opt => copy_array($value));
    ();
  } else {
    copy_array($value);
  }
}

sub define {
  my ($class, $method, $sub) = @_;
  # XXX: API 以外の関数は弾くべきかもしれない。
  *{globref($class, $method)} = $sub;
}

1;
