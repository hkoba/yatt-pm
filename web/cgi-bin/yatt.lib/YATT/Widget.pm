# -*- mode: perl; coding: utf-8 -*-
package YATT::Widget;
use strict;
use warnings FATAL => qw(all);

use Exporter qw(import);

use base qw(YATT::Class::Configurable);
use YATT::Fields qw(^=arg_dict
		    ^=arg_order
		    ^=argmacro_dict
		    ^=argmacro_order
		    ^cf_root
		    cf_name
		    cf_filename
		    cf_decl_start
		    cf_body_start
		    cf_template_nsid
		    ^cf_no_last_newline
		  );

use YATT::Types qw(:export_alias)
  , -alias => [Cursor => 'YATT::LRXML::NodeCursor'
	       , Widget => __PACKAGE__];
use YATT::LRXML::Node qw(create_node);
use YATT::Util qw(add_arg_order_in call_type);

use Carp;

sub after_configure {
  my MY $widget = shift;
  $widget->{cf_root} ||= $widget->create_node('root');
}

sub cursor {
  my Widget $widget = shift;
  $widget->call_type(Cursor => new_opened => $widget->{cf_root}, @_);
}

sub add_arg {
  (my Widget $widget, my ($name, $arg)) = @_;
  add_arg_order_in($widget->{arg_dict}, $widget->{arg_order}, $name, $arg);
  $widget;
}

sub has_arg {
  (my Widget $widget, my ($name)) = @_;
  defined $widget->{arg_dict}{$name};
}

sub arg_specs {
  (my Widget $widget) = @_;
  my @list = ($widget->{arg_dict} ||= {}
	      , $widget->{arg_order} ||= []);
  wantarray ? @list : \@list;
}

sub macro_specs {
  (my Widget $widget) = @_;
  my @list = ($widget->{argmacro_dict} ||= {}
	      , $widget->{argmacro_order} ||= []);
  wantarray ? @list : \@list;
}

sub reorder_params {
  (my Widget $widget, my ($params)) = @_;
  my @params;
  foreach my $name (map($_ ? @$_ : (), $widget->{arg_order})) {
    push @params, delete $params->{$name};
  }
  if (keys %$params) {
    die "Unknown args for $widget->{cf_name}: " . join(", ", keys %$params);
  }
  wantarray ? @params : \@params;
}

1;
