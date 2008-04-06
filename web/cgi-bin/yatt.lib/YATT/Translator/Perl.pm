# -*- mode: perl; coding: utf-8 -*-
package YATT::Translator::Perl; use YATT::Inc;
use strict;
use warnings FATAL => qw(all);
use Carp;

#========================================

our %TYPE_MAP;

use base qw(YATT::Registry);
use YATT::Fields [cf_mode => 'render']
  , [cf_product => sub {[]}]
  , qw(target_cache
       cf_debug_translator);

use YATT::Registry::NS;
use YATT::Widget;
use YATT::Util qw(checked_eval add_arg_order_in terse_dump coalesce);
use YATT::LRXML::Node qw(node_path node_body node_name node_children
			 create_node
			 TEXT_TYPE ELEMENT_TYPE ENTITY_TYPE);

use YATT::LRXML::EntityPath;
use YATT::Util::Taint;
use YATT::Util::Symbol qw(declare_alias);

#========================================

sub qqvalue ($);
sub qparen ($);

#========================================

sub after_configure {
  my MY $trans = shift;
  $trans->SUPER::after_configure;
  $trans->{cf_type_map} ||= \%TYPE_MAP;
}

sub emit {
  my MY $gen = shift;
  my $script = join "", @{$gen->{cf_product}};
  $gen->{cf_product} = [];
  $script;
}

#========================================

sub call_handler {
  (my MY $trans, my ($method, $widget_path)) = splice @_, 0, 3;
  my ($handler, $pkg) = $trans->get_handler_to
    ($method, ref $widget_path ? @$widget_path : split /[:\.]/, $widget_path);
  &YATT::break_handler;
  $handler->($pkg, @_);
}

sub get_handler_to {
  (my MY $trans, my ($method, @elpath)) = @_;

  if (@elpath == 1) {
    if (ref $elpath[0]) {
      @elpath = @{$elpath[0]};
    } else {
      @elpath = split '/', $elpath[0];
      shift @elpath if !defined $elpath[0] || $elpath[0] eq '';
    }
  }

  $trans->{cf_mode} = $method; # XXX: local
  @{$trans->{cf_product}} = ();

  my Widget $widget = $trans->get_widget(@elpath)
    or carp "Can't find widget: " . join(":", @elpath);
  $trans->ensure_widget_is_generated($widget);
  if (my $script = $trans->emit) {
    print STDERR $script if $trans->{cf_debug_translator};
    $trans->checked_eval
      (join(";"
	    , 'use strict'
	    , 'use warnings FATAL => qw(all)'
	    # XXX: 何が redefine されるかは分からないから…
	    , 'no warnings "redefine"'
	    , untaint_any($script)));

  }
  my ($pkg, $funcname) = $trans->get_funcname_to($method, $widget);
  my $handler = $pkg->can($funcname);

  return $handler unless wantarray;
  ($handler, scalar $trans->get_package_from_widget($widget));
}

sub get_funcname_to {
  (my MY $trans, my ($mode), my Widget $widget) = @_;
  my $pkg = $trans->get_package_from_widget($widget);
  my $fname = "${mode}_$$widget{cf_name}";
  wantarray ? ($pkg, $fname) : join("::", $pkg, $fname);
}

sub get_package_from_widget {
  (my MY $trans, my Widget $widget) = @_;
  my $primary = $trans->get_package
    (my Template $tmpl = $trans->nsobj($widget->{cf_template_nsid}));

  return $primary unless wantarray;
  ($primary, $trans->get_rc_package_from_template($tmpl));
}

sub get_rc_package_from_template {
  (my MY $trans, my Template $tmpl) = @_;
  $trans->get_package($trans->nsobj($tmpl->{cf_parent_nsid}));
}

#----------------------------------------

sub generate {
  my MY $gen = shift;
  foreach my $elempath (@_) {
    if (my $widget = $gen->get_widget(@$elempath)) {
      $gen->ensure_widget_is_generated($widget);
    } elsif (my $ns = $gen->get_ns($elempath)) {
      $gen->ensure_ns_is_generated($ns);
    } else {
      croak "Invalid widget path: " . join(":", @$elempath);
    }
  }
  $gen->emit;
}

sub ensure_widget_is_generated {
  (my MY $gen, my Widget $widget) = @_;
  $gen->ensure_template_is_generated($widget->{cf_template_nsid});
}

sub ensure_template_is_generated {
  (my MY $gen, my $tmplid) = @_;
  $tmplid = $tmplid->cget('nsid') if ref $tmplid;
  return if $gen->{target_cache}{$tmplid}++;

  # eval は？
  push @{$$gen{cf_product}}
    , $gen->generate_template($gen->nsobj($tmplid));
}

sub forget_template {
  (my MY $gen, my $tmplid) = @_;
  $tmplid = $tmplid->cget('nsid') if ref $tmplid;
  delete $gen->{target_cache}{$tmplid} ? 1 : 0;
}

sub generate_template {
  (my MY $gen, my Template $tmpl) = @_;
  print STDERR "Generate: $tmpl->{cf_loadkey}\n"
    if $gen->{cf_debug_translator};
  my $metainfo = $tmpl->metainfo;
  join "", q{package } . $gen->get_package($tmpl) . ';'
    , map {$gen->generate_widget($_, $metainfo)} @{$tmpl->widget_list};
}

my %calling_conv;

sub generate_lineinfo {
  (my MY $gen, my Widget $widget, my ($start)) = @_;
  return if $gen->{cf_no_lineinfo};
  sprintf qq{#line %d "%s"\n}, $start, $widget->{cf_filename};
}

sub generate_widget {
  (my MY $gen, my Widget $widget, my ($metainfo)) = @_;
  my @body = $gen->generate_body
    ([{}
      , [$widget->arg_dict
	 , [\%calling_conv]]]
     , $widget->cursor(metainfo => $metainfo->clone
		       (startline => $widget->{cf_body_start})));
  # body が空の場合もありうる。
  return unless @body;
  my ($pkg, $funcname) = $gen->get_funcname_to($gen->{cf_mode}, $widget);
  join(""
       , "\n", $gen->generate_lineinfo($widget, $widget->{cf_decl_start})
       , $gen->generate_getargs($widget, $metainfo)
       , $gen->generate_lineinfo($widget, $widget->{cf_body_start})
       , $gen->as_sub
       ($funcname
	, $gen->genprolog($widget)
	, $gen->as_statement_list(@body)));
}

sub generate_getargs {
  (my MY $gen, my Widget $widget, my ($metainfo)) = @_;
  $gen->as_sub("getargs_$$widget{cf_name}", sprintf q{
   my ($call) = shift;
   $_[0] = shift @$call; shift;
   my $args = $_[0] = shift @$call; shift;
   if (ref $args eq 'ARRAY') {
%s} else {
%s
}
}
	       , $gen->gen_getargs_static($widget, $metainfo)
	       , $gen->gen_getargs_dynamic($widget, $metainfo));
}

sub genprolog {
  (my MY $gen, my Widget $widget) = @_;
  my @args = qw($this $args);
  if ($widget->{arg_order} && @{$widget->{arg_order}}) {
    foreach my $name (@{$widget->{arg_order}}) {
      push @args, $widget->{arg_dict}{$name}->as_lvalue
    }
  }
  sprintf q{getargs_%s(\@_, my (%s))}
    , $$widget{cf_name}, join(", ", @args);
}

sub generate_body {
  (my MY $gen, my ($scope, $cursor)) = @_;
  my @code;
  for (; $cursor->readable; $cursor->next) {
    if (my $sub = $gen->can("trans_" . (my $t = $cursor->node_type_name))) {
      push @code, $sub->($gen, $scope, $cursor);
    } else {
      die $gen->node_error($cursor, "Can't handle node type: %s", $t);
    }
  }
  @code;
}

sub as_sub {
  my ($gen, $func_name) = splice @_, 0, 2;
  "sub $func_name ". $gen->as_block(@_) . "\n";
}

sub as_block {
  my ($gen) = shift;
  return '{}' unless @_;
  my $last = pop;
  $last .= do {
    if ($last =~ s/(\n+)$//) {
      "}$1";
    } else {
      '}';
    }
  };
  '{ '.join("; ", @_, $last);
}

sub as_join {
  my MY $gen = shift;
  my (@result);
  foreach my $trans (@_) {
    if (ref $trans) {
      push @result, qq(YATT::capture {$$trans});
    } else {
      push @result, $trans;
    }
  }
  sprintf q{join('', %s)}, join ", ", @result;
}

use YATT::Types
  [queued_joiner => [qw(queue printable last_ws)]];

sub YATT::Translator::Perl::queued_joiner::joiner {
  # 生の join では常に , が入るが、 print , になって困る。
  (my queued_joiner $me, my ($head)) = splice @_, 0, 2;
  my ($line, @result, $argc, $nlines) = ('');
  foreach my $i (@_) {
    if ($i =~ /\S/) {
      $line .= ', ' if length($line);
      $line .= $i;
    } else {
      $line .= $i;
    }
    if ($i =~ /\n/) {
      push @result, $line;
      $line = '';
    }
  }
  push @result, $line if $line ne '';
  # XXX: もっと整理せよ。
  map {/\S/ ? $head . $_ : $_} @result;
}

sub YATT::Translator::Perl::queued_joiner::add {
  (my queued_joiner $me, my $str) = @_;
  push @{$me->{queue}}, $str;
  if ($str =~ /\S/) {
    $me->{printable}++;
    undef $me->{last_ws};
  } else {
    $me->{last_ws} = 1;
  }
}

sub YATT::Translator::Perl::queued_joiner::emit_to {
  (my queued_joiner $me, my ($result)) = @_;
  if ($me->{printable}) {
    my $ws = pop @{$me->{queue}} if $me->{last_ws};
    push @$result, $me->joiner('print ', @{$me->{queue}}) if @{$me->{queue}};
    $result->[-1] .= $ws if $me->{last_ws};
  }
  undef @{$me->{queue}};
  undef $me->{printable};
  undef $me->{last_ws};
}

sub as_statement_list {
  my MY $gen = shift;
  my queued_joiner $queue = queued_joiner->new;
  my (@result);
  foreach my $trans (@_) {
    if (ref $trans) {
      $queue->emit_to(\@result);
      push @result, $$trans;
    } else {
      $queue->add($trans);
    }
  }
  $queue->emit_to(\@result);
  @result;
}

#----------------------------------------
# trans_zzz

sub trans_comment {
  (my MY $trans, my ($scope, $node)) = @_;
  \ ("\n" x $node->node_nlines);
}

sub trans_text {
  (my MY $trans, my ($scope, $node)) = @_;
  my $body = $node->current;
  my ($pre, $post) = ('', '');
  if ($node->node_is_beginning) {
    $pre = $1 if $body =~ s/^(\n+)//;
  } elsif ($node->node_is_end) {
    $post = $1 if $body =~ s/\n(\n+)$/\n/;
  }
  $pre.do {
    if ($body eq '') {
      ''
    } elsif ($body eq "\n") {
      '"\n"'."\n";
    } else {
      qparen($body);
    }
  }.$post;
}

sub trans_pi {
  (my MY $trans, my ($scope, $node)) = @_;
  my $body = $trans->genexpr_node($scope, 0, $node->open);
  if ($body =~ s/^=//) {
    qq{YATT::escape(do {$body})}
  } else {
    \ $body;
  }
}

sub genexpr_node {
  (my MY $trans, my ($scope, $early_escaped, $node)) = @_;
  join("", map { ref $_ ? $$_ : $_ }
       $trans->mark_vars($scope, $early_escaped, $node));
}

#========================================

use YATT::Util::Enum -prefix => 'ENT_', qw(RAW ESCAPED PRINTED);

sub trans_entity {
  (my MY $trans, my ($scope, $node)) = @_;
  $trans->generate_entref($scope, ENT_PRINTED, $node);
}

sub trans_html {
  (my MY $trans, my ($scope, $node)) = @_;
  my $tag = $node->node_name;
  my ($string, $tagc, $end) = do {
    if ($node->is_empty_element) {
      ("<$tag", " />", '');
    } else {
      ("<$tag", ">", "</$tag>");
    }
  };

  my $item = $node->open;
  my @script;
  for (; $item->readable; $item->next) {
    last unless $item->is_primary_attribute;
    $string .= ' ';
    my ($open, $close) = $item->node_attribute_format;
    $string .= $open;
    for (my $frag = $item->open; $frag->readable; $frag->next) {
      my $type = $frag->node_type;
      if ($type == TEXT_TYPE) {
	$string .= $frag->current;
      } elsif ($type == ENTITY_TYPE) {
	# should be entity
	push @script, qparen($string)
	  , $trans->generate_entref($scope, ENT_ESCAPED, $frag);
	$string = '';
      } else {
	die $trans->node_error($frag, "Invalid node in html attribute");
      }
    }
    $string .= $close;
  }

  $string .= $tagc if $tagc ne '';
  for (; $item->readable; $item->next) {
    if ($item->node_type == TEXT_TYPE) {
      $string .= $item->current;
    } else {
      push @script, qparen($string), $trans->generate_body($scope, $item);
      $string = '';
    }
  }
  $string .= $end if $end;
  push @script, qparen($string) if $string ne '';
  @script;
}

#========================================

my %control = (if => undef, unless => undef);
sub trans_element {
  (my MY $trans, my ($scope, $node)) = @_;
  my $tmpl = $trans->get_template_from_node($node);

  # ■ 最初に要素マクロ ← RC から検索。
  if (my $macro = $trans->has_element_macro($tmpl, $node, $node->node_path)) {
    # XXX: ssri:foreach → yatt:foreach も。
    return $macro->($trans, $scope, $node->open);
  }

  # ■ 次に if/unless/else,
  if (my @arm = $trans->collect_arms($node, else => \%control)) {
    return $trans->gencall_conditional($scope, @arm);
  }

  # ■ 無条件呼び出し
  $trans->gencall_always($scope, $node);
}

sub gencall_conditional {
  (my MY $trans, my ($scope, $ifunless, @elses)) = @_;
  my $pkg;
  my $script = do {
    my ($cond, $action) = @$ifunless; # (node, cursor)
    sprintf(q{%s (%s) {%s}}
	    , $cond->node_name
	    , $trans->genexpr_node($scope, 0, $cond->open)
	    , ${ $trans->gencall_always($scope, $action->make_wrapped) });
  };

  foreach my $arm (@elses) {
    my ($cond, $action) = @$arm;
    $script .= do {
      if ($cond) {
	sprintf q{ elsif (%s) }
	  , $trans->genexpr_node($scope, 0, $cond->open);
      } else {
	q{ else }
      }
    };
    $script .= sprintf q{{%s}}
      , ${ $trans->gencall_always($scope, $action->make_wrapped) };
  }
  \ $script;
}

sub gencall_always {
  (my MY $trans, my ($scope, $node)) = @_;

  my $tmpl = $trans->get_template_from_node($node);
  my @elempath = $node->node_path
    or die $trans->node_error($node, "Empty element path");

  # ■ 局所引数
  if (my $codevar = $trans->find_codearg($scope, @elempath)) {
    # ← 特に、親の call の body の中で、<yatt:body foo=bar/> で
    # 呼ばれるとき, だよね？
    unless (ref $codevar and $codevar->can('arg_specs')) {
      die $trans->node_error($node, "Invalid codevar $codevar for @elempath");
    }

    my @args = $trans->genargs_static
      ($scope, $node->open, $codevar->arg_specs);
    return \ sprintf '%1$s && %1$s->(%2$s)', $codevar->as_lvalue
      , join(", ", @args);
  }

  # ■ さもなければ、通常の Widget の呼び出し
  my Widget $widget = $trans->get_widget_from_template($tmpl, @elempath);
  unless ($widget) {
    die $trans->node_error($node, "No such widget");
  }
  $trans->gencall($widget, $scope, $node->open);
}

sub gencall {
  (my MY $trans, my Widget $widget, my ($scope, $node)) = @_;
  $trans->ensure_widget_is_generated($widget);

  # 引数マクロの抜き出し
  if (my $macros = $widget->{argmacro_dict}) {
    $node = YATT::ArgMacro->expand_all_macros
      ($trans, $scope, $node, $macros, $widget->{argmacro_order});
  }

  my $func = $trans->get_funcname_to($trans->{cf_mode}, $widget);
  # actual 一覧の作成
  my @args = $trans->genargs_static($scope, $node
				    , @{$widget}{qw(arg_dict arg_order)});

  # XXX: calling convention 周り
  return \ sprintf(' %s($this, [%s])', $func
		   , join(", ", map {defined $_ ? $_ : 'undef'} @args));
}

sub genargs_static {
  (my MY $trans, my ($scope, $args, $arg_dict, $arg_order)) = @_;
  my ($body, @actual) = $args->variant_builder;
  for (my $nth = 0; $args->readable; $args->next) {
    unless ($args->is_attribute) {
      $body->add_node($args->current);
      next;
    }

    my ($typename, $name) = (undef, $args->node_name);
    unless (defined $name) {
      $name = $arg_order->[$nth++]
	or die $trans->node_error($args, "Too many args");
    } elsif (ref $name) {
      ($typename, $name) = @$name;
    }
    my $argdecl = $arg_dict->{$name}
      or die $trans->node_error($args, "Unknown arg '%s'", $name);
    # XXX: $typename (type:attname の type) を活用していない。
    # XXX: code 型引数を primary で渡したときにまで、 print が作られてる。
    # $args->is_quoted_by_element で判別せよ。
    $actual[$argdecl->argno] = do {
      if (defined $args->node_body) {
	$argdecl->gen_assignable_node($trans, $scope, $args);
      } elsif (my $var = $trans->find_var($scope, $name)) {
	# bare 渡し (name=value の value が省略されていて、
	# 同じ名前の変数が有った場合、pass thru)
	$argdecl->early_escaped ? $var->as_escaped : $var->as_lvalue;
      } else {
	die $trans->node_error($args, "value-less arg must has same var %s"
			       , $name);
      }
    };
  }
  if ($body->array_size
      and my $bodydecl = $arg_dict->{body}) {
    # if $actual[$bodydecl->argno]; なら、エラーを報告すべきでは?
    # code か、html か。
    $actual[$bodydecl->argno]
      = $bodydecl->gen_assignable_node($trans, $scope, $body, 1);
  }
  @actual;
}

sub collect_arms {
  my ($pack, $call, $key, $dict) = @_;
  my ($type, $name) = $call->node_headings;
  my $args = $call->open;
  my ($cond, $body) = $pack->consume_arm($args, $dict, $type, $name
					 , primary_only => 1);
  return unless $cond;
  my @case = [$cond, $body];
  for (; $args->readable; $args->next) {
    if ($args->is_attribute && $args->node_name eq $key) {
      push @case, [$pack->consume_arm($args->open, $dict, $type, $name)];
    } else {
      # XXX: 多分、$case[0] (== $body)
      $case[-1][-1]->add_node($args->current);
    }
  }
  @case;
}

sub consume_arm {
  my ($trans, $node, $dict, $type, $name, @opts) = @_;
  my $arm = $node->variant_builder($type, $name);
  my @cond = $arm->filter_or_add_from($node, $dict, @opts);
  if (@cond >= 2) {
    die $trans->node_error
      ($node, "Too many condtitions: %s"
       , join("", map {stringify_node($_)} @cond));
  }
  # $cond[0] は undef かもしれない。 ex. <:else/>

  my $cond = $trans->fake_cursor_from($arm, $cond[0]) if defined $cond[0];
  ($cond, $arm);
}

#----------------------------------------

sub has_element_macro {
  (my MY $trans, my Template $tmpl, my ($node, @elempath)) = @_;
  # XXX: macro の一覧は、ちゃんと取り出せるか?

  if (@elempath > 2) {
    # Not implemented.
    return;
  }

  my $pkg = $trans->get_rc_package_from_template($tmpl);
  foreach my $shift (0, 1) {
    my $sysns = $trans->shift_sysns(\@elempath) if $shift;

    my $macro_name = join("_", macro => @elempath);

    if (my $sub = $pkg->can($macro_name) || $trans->can($macro_name)) {
      return $sub;
    }
  }
}

#========================================
# 宣言関連

# XXX: use は perl 固有だから、ここに持たせるのは理にかなう。
sub declare_use {
}

sub after_define_args {
  (my MY $trans, my ($target)) = @_;
  unless ($target->has_arg('body')) {
    $target->add_arg(body => $trans->create_var('code'));
  }
  $trans;
}

# For ArgMacro
sub add_decl_entity {
  (my MY $trans, my Widget $widget, my ($node)) = @_;
  foreach my $pkg ($trans->get_package_from_widget($widget)) {
    my $macro = $pkg->can('ArgMacro_' . $node->node_nsname('', '_'))
      or next;
    my $macro_class = $macro->();
    unless ($macro_class->can('handle')) {
      die $trans->node_error
	($node, "ArgMacro doesn't implement ->handle method: %s"
	 , $node->node_name);
    }
    return $macro_class->register_in
      ($trans, scalar $widget->macro_specs, $widget);
  }
  die $trans->node_error($node, "No such ArgMacro: %s"
			 , $node->node_name);
}

#========================================
# 変数関連

use YATT::Types [VarType =>
		 [qw(cf_varname ^cf_argno cf_default cf_default_mode)]]
  , qw(:export_alias);

sub find_var {
  (my MY $trans, my ($scope, $varName)) = @_;
  for (; $scope; $scope = $scope->[1]) {
    carp "Undefined varName!" unless defined $varName;
    if (defined (my $value = $scope->[0]{$varName})) {
      return $value;
    }
  }
  undef;
}

sub find_codearg {
  (my MY $trans, my ($scope, @elempath)) = @_;
  return if @elempath >= 3;
  $trans->shift_sysns(\@elempath);
  return unless @elempath == 1;
  my $var = $trans->find_var($scope, $elempath[0])
    or return;
  return unless ref $var and $var->can('arg_specs');
  $var;
}

sub gen_getargs_static {
  (my MY $gen, my Widget $widget, my ($metainfo)) = @_;
  my (@args, %scope);
  foreach my $name ($widget->{arg_order} ? @{$widget->{arg_order}} : ()) {
    my VarType $var = $widget->{arg_dict}{$name};
    $scope{$name} = $var;
    my $decl = sprintf q{my %s = $_[%d]}, $var->as_lvalue, $$var{cf_argno};
    my $value = $var->gen_getarg
      ($gen, [\%scope], $widget, $metainfo, qq{\$args->[$$var{cf_argno}]});
    push @args, "$decl = $value;\n";
  }
  join "", @args;
}

sub gen_getargs_dynamic {
  '';
}

sub mark_vars {
  (my MY $trans, my ($scope, $early_escaped, $node)) = @_;
  my @result;
  for (; $node->readable; $node->next) {
    if ($node->node_type == TEXT_TYPE) {
      # XXX: dots_for_arrows
      push @result, $node->current;
    } elsif ($node->node_type == ELEMENT_TYPE) {
      push @result, \ $trans->generate_captured($scope, $node);
    } else {
      push @result, \ $trans->generate_entref($scope, $early_escaped, $node);
    }
  }
  @result;
}

sub feed_array_if {
  (my MY $trans, my ($name, $array)) = @_;
  return unless @$array >= 1;
  return unless $array->[0][0] eq $name;
  my $desc = shift @$array;
  wantarray ? @{$desc}[1..$#$desc] : $desc;
}

sub gen_entref_path {
  (my MY $trans, my ($scope, $node)) = splice @_, 0, 3;

  my @expr = do {
    if (my ($name, @args) = $trans->feed_array_if(call => \@_)) {
      my $pkg = $trans->get_package_from_node($node);
      my $call = do {
	# XXX: codevar は、path の先頭だけ。
	# 引数にも現れるから、
	if (my $var = $trans->find_var($scope, $name)) {
	  if (ref $var and $var->can('arg_specs')) {
	    sprintf('%1$s && %1$s->', $var->as_lvalue);
	  } else {
	    $var->as_lvalue;
	  }
	} elsif ($pkg->can(my $en = "entity_$name")) {
	  sprintf('%s->%s', $pkg, $en);
	} else {
	  die $trans->node_error($node, "not implemented call '%s' in %s"
				 , $name, $node->node_body);
	}
      };

      $call.'('.join(", ", map {
	$trans->gen_entref_path($scope, $node, $_)
      } @args).')';
    } elsif (($name) = $trans->feed_array_if(var => \@_)) {
      unless (my $var = $trans->find_var($scope, $name)) {
	die $trans->node_error($node, "No such variable '%s'", $name);
      } else {
	$var->as_lvalue;
      }
    } elsif (($name) = $trans->feed_array_if(text => \@_)) {
      qqvalue($name);
    } else {
      die $trans->node_error($node, "NIMPL(%s)", terse_dump(@_));
    }
  };
  foreach my $item (@_) {
    my ($type, $name, @args) = @$item;
    push @expr, do {
      if ($type eq 'call') {
	$name. '('.join(", ", map {
	  $trans->gen_entref_path($scope, $node, $_)
	} @args).')';
      } elsif ($type eq 'var') {
	sprintf('{%s}', qqvalue($name));
      } elsif ($type eq 'aref') {
	sprintf('[%s]', $name);
      } else {
	die $trans->node_error($node, "NIMPL(type=$type)");
      }
    };
  }
  join("->", @expr);
}

sub find_if_codearg {
  (my MY $trans, my ($scope, $node, $entpath)) = @_;
  my @entns = $node->node_path;
  return unless $trans->shift_sysns(\@entns);
  return if @entns;
  return unless @$entpath == 1;
  return unless $entpath->[0][0] eq 'call';
  my ($op, $name, @args) = @{$entpath->[0]};
  my $codearg = $trans->find_codearg($scope, $name)
    or return;
  ($codearg, @args);
}

sub generate_entref {
  (my MY $trans, my ($scope, $escaped, $node)) = @_;
  my $is_sysns = $trans->shift_sysns(my $entns = [$node->node_path]);
  my $body = $node->node_body;
  substr($body, 0, 0) = ':' if defined $body and not defined $node->node_name;
  my @entpath = $trans->parse_entpath(join('', map {':'.$_} @$entns)
				      . coalesce($body, ''));

  # 特例。&yatt:codevar(); は、副作用で print.
  if ($escaped == ENT_PRINTED
      and my ($codearg, @args)
      = $trans->find_if_codearg($scope, $node, \@entpath)) {
    return \ sprintf('%1$s && %1$s->(%2$s)', $codearg->as_lvalue
		     , join(", ", map {
		       $trans->gen_entref_path($scope, $node, $_)
		     } @args));
    # 引数。
  }
  if ($body || @$entns > 1) {
    # path が有る。
    my $expr = $trans->gen_entref_path($scope, $node, @entpath);
    # XXX: sub { print } なら \ $expr にすべきだが、
    #  sub { value } などは、むしろ YATT::escape(do {$expr}) すべき。
    return $escaped ? qq(YATT::escape($expr)) : $expr;
  }

  my $varName = shift @$entns;
  my $vardecl = $trans->find_var($scope, $varName)
    or die $trans->node_error($node, "No such variable '%s'", $varName);

  $escaped ? $vardecl->as_escaped : $vardecl->as_lvalue;
}

#========================================

sub YATT::Translator::Perl::VarType::gen_getarg {
  (my VarType $var, my MY $gen
   , my ($scope, $widget, $metainfo, $actual)) = @_;
  return $actual unless defined $var->{cf_default}
    and defined (my $mode = $var->{cf_default_mode});
  my ($cond) = do {
    if ($mode eq "|") {
      qq{$actual}
    } elsif ($mode eq "?") {
      qq{defined $actual && $actual ne ""}
    } elsif ($mode eq "/") {
      qq{defined $actual}
    } else {
      die "Unknown defaulting mode: $mode"
    }
  };

  my $default = $var->gen_assignable_node
    ($gen, $scope
     , $gen->fake_cursor($widget, $metainfo
			 , map {ref $_ ? @$_ : $_} $var->{cf_default})
     , 1);

  qq{($cond ? $actual : $default)};
}

sub YATT::Translator::Perl::VarType::gen_assignable_node {
  (my VarType $var, my MY $trans, my ($scope, $node, $is_opened)) = @_;
  # early escaped な変数への代入値は、代入前に escape される。
  my $escaped = $var->early_escaped;
  $var->quote_assignable
    ($trans->mark_vars($scope, $escaped, $is_opened ? $node : $node->open));
}

sub YATT::Translator::Perl::VarType::can_call { 0 }
sub YATT::Translator::Perl::VarType::early_escaped { 0 }
sub YATT::Translator::Perl::VarType::lvalue_format {'$%s'}
sub YATT::Translator::Perl::VarType::as_lvalue {
  my VarType $var = shift;
  sprintf $var->lvalue_format, $var->{cf_varname};
}

sub YATT::Translator::Perl::VarType::escaped_format {'YATT::escape($%s)'}

sub YATT::Translator::Perl::VarType::as_escaped {
  my VarType $var = shift;
  sprintf $var->escaped_format, $var->{cf_varname};
}

use YATT::ArgTypes
  (-type_map => \%TYPE_MAP
   , -base => VarType
   , -type_fmt => join("::", MY, 't_%s')
   , [text => -alias => '']
   , [html => \ lvalue_format => '$html_%s', \ early_escaped => 1]
   , [scalar => -alias => 'value']
   , ['list']
   , [attr => -base => 'html']
   , [code   => -alias => 'expr', \ can_call => 1
      # 引数の型情報
      , -fields => [qw(arg_dict arg_order)]]
   , qw(:type_name)
  );

$calling_conv{this} = t_scalar->new(varname => 'this');
$calling_conv{args} = t_scalar->new(varname => 'args');

sub YATT::Translator::Perl::t_text::quote_assignable {
  shift;
  'qq('.join("", map { ref $_ ? '@{['.$$_.']}' : paren_escape($_) } @_).')';
}

sub YATT::Translator::Perl::t_html::escaped_format {shift->lvalue_format}

sub YATT::Translator::Perl::t_html::gen_assignable_node {
  (my VarType $var, my MY $trans, my ($scope, $node, $is_opened)) = @_;
  # XXX: フラグがダサい。
  $trans->as_join
    ($trans->generate_body($scope, $is_opened ? $node : $node->open));
}

sub YATT::Translator::Perl::t_attr::gen_getarg {
  (my t_attr $var, my MY $gen
   , my ($scope, $widget, $metainfo, $actual)) = @_;
  $actual;
}

sub YATT::Translator::Perl::t_attr::as_escaped {
  my t_attr $var = shift;
  my $realvar = sprintf $var->lvalue_format, $var->{cf_varname};
  sprintf(q{%2$s ? qq( %1$s="%2$s") : ''}
	  , $var->{cf_default} || $var->{cf_varname}
	  , $realvar);
}

sub YATT::Translator::Perl::t_scalar::quote_assignable {
  shift;
  'scalar(do {'.join("", map { ref $_ ? $$_ : $_ } @_).'})';
}

sub YATT::Translator::Perl::t_list::quote_assignable {
  shift;
  '['.join("", map { ref $_ ? $$_ : $_ } @_).']';
}

sub YATT::Translator::Perl::t_code::arg_specs {
  my t_code $argdecl = shift;
  ($argdecl->{arg_dict} ||= {}, $argdecl->{arg_order} ||= []);
}

sub YATT::Translator::Perl::t_code::gen_args {
  (my t_code $argdecl) = @_;
  return unless $argdecl->{arg_order}
    && (my @args = @{$argdecl->{arg_order}});
  \ sprintf('my (%s) = @_', join(", ", map {
    $argdecl->{arg_dict}{$_}->as_lvalue;
  } @args));
}

sub YATT::Translator::Perl::t_code::gen_body {
  (my t_code $argdecl, my MY $trans, my ($scope, $is_expr, $node)) = @_;
  return unless $node->array_size;
  if ($is_expr) {
    $trans->genexpr_node($scope, ENT_RAW, $node);
  } else {
    $trans->as_statement_list
      ($argdecl->gen_args
       , $trans->generate_body([$argdecl->{arg_dict}, $scope], $node));
  }
}

sub YATT::Translator::Perl::t_code::gen_assignable_node {
  (my t_code $argdecl, my MY $trans, my ($scope, $node, $is_opened)) = @_;
  my $is_expr = !$is_opened && !$node->is_quoted_by_element;
  $trans->as_sub('', $argdecl->gen_body($trans, $scope, $is_expr
					, $is_opened ? $node : $node->open));
}

sub YATT::Translator::Perl::t_code::has_arg {
  (my t_code $argdecl, my ($name)) = @_;
  defined $argdecl->{arg_dict}{$name};
}

sub YATT::Translator::Perl::t_code::add_arg {
  (my t_code $codevar, my ($name, $arg)) = @_;
  add_arg_order_in($codevar->{arg_dict}, $codevar->{arg_order}, $name, $arg);
  $codevar;
}

# code 型の変数宣言の生成
sub create_var_code {
  (my MY $trans, my ($node, @param)) = @_;
  my t_code $codevar = $trans->t_code->new(@param);
  $trans->define_args($codevar, $node->open) if $node;
  $codevar;
}

#========================================

sub make_arg_spec {
  my ($dict, $order) = splice @_, 0, 2;
  foreach my $name (@_) {
    $dict->{$name} = @$order;
    push @$order, $name;
  }
}

sub feed_arg_spec {
  (my MY $trans, my ($args, $arg_dict, $arg_order)) = splice @_, 0, 4;
  my $found;
  for (my $nth = 0; $args->readable; $args->next) {
    last unless $args->is_primary_attribute;
    my ($typename, $name) = (undef, $args->node_name);
    unless (defined $name) {
      $name = $arg_order->[$nth++]
	or die $trans->node_error($args, "Too many args");
    } elsif (ref $name) {
      ($typename, $name) = @$name;
    }
    defined (my $argno = $arg_dict->{$name})
      or die $trans->node_error($args, "Unknown arg '%s'", $name);

    $_[$argno] = $args->current;
    $found++;
  }
  $found;
}

{
  # list=list/value, my=text, ith=text
  make_arg_spec(\ my %arg_dict, \ my @arg_order
		, qw(list my ith));

  declare_alias macro_yatt_foreach => \&macro_foreach;
  sub macro_foreach {
    (my MY $trans, my ($scope, $args, $fragment)) = @_;

    $trans->feed_arg_spec($args, \%arg_dict, \@arg_order
			  , my ($list, $my, $ith))
      or die $trans->node_error($args, "Not enough arguments");

    unless (defined $list) {
      die $trans->node_error($args, "no list= is given");
    }

    # $ith をまだ使っていない。
    my %local;
    my $loopvar = do {
      if ($my) {
	my $varname = node_body($my);
	$local{$varname} = $trans->create_var('', undef, varname => $varname);
	'my $' . $varname;
      } else {
	# _ は？ entity 自体に処理させるか…
	''
      }
    };

    my $fmt = q{foreach %1$s (%2$s) %3$s};
    my $listexpr = $trans->genexpr_node($scope, 0, $args->adopter_for($list));
    my @statements = $trans->as_statement_list
      ($trans->generate_body([\%local, $scope], $args));

    if ($fragment) {
      ($fmt, $loopvar, $listexpr, \@statements);
    } else {
      \ sprintf $fmt, $loopvar, $listexpr, $trans->as_block(@statements);
    }
  }
}

{
  # if
  make_arg_spec(\ my %arg_dict, \ my @arg_order
		, qw(if unless));
  sub gen_macro_if_arm {
    (my MY $trans, my ($scope, $primary, $pkg, $if, $unless, $body)) = @_;
    my $header = do {
      if ($primary) {
	my ($kw, $cond) = do {
	  if ($if) { (if => $if) }
	  elsif ($unless) { (unless => $unless) }
	  else { die "??" }
	};
	sprintf q{%s (%s) }, $kw
	  , $trans->genexpr_node($scope, 0
				 , $trans->fake_cursor_from($body, $cond, 1));
      } else {
	my ($cond, $true) = do {
	  if ($if) { ($if, 1) }
	  elsif ($unless) { ($unless, 0) }
	  else {}
	};
	unless (defined $cond) {
	  q{else }
	} else {
	  my $expr = $trans->genexpr_node
	    ($scope, 0
	     , $trans->fake_cursor_from($body, $cond, 1));
	  sprintf q{elsif (%s) }, $true ? $expr : qq{not($expr)};
	}
      }
    };
    $header . $trans->as_block
      ($trans->as_statement_list
       ($trans->generate_body($scope, $body)));
  }

  declare_alias macro_yatt_if => \&macro_if;
  sub macro_if {
    (my MY $trans, my ($scope, $args)) = @_;

    my @case = do {
      $trans->feed_arg_spec($args, \%arg_dict, \@arg_order
			    , my ($if, $unless))
	or die $trans->node_error($args, "Not enough arguments");
      ([$if, $unless, $args->variant_builder]);
    };
    for (; $args->readable; $args->next) {
      if ($args->is_attribute && $args->node_name eq 'else') {
	my $kid = $args->open;
	$trans->feed_arg_spec($kid, \%arg_dict, \@arg_order
			      , my ($if, $unless));
	push @case, [$if, $unless, $kid];
      } else {
	# XXX: 多分、$case[0]
	$case[-1][-1]->add_node($args->current);
      }
    }

    my $pkg = $trans->get_package_from_node($args);
    my @script = $trans->gen_macro_if_arm($scope, 1, $pkg, @{shift @case});
    while (my $arm = shift @case) {
      push @script, $trans->gen_macro_if_arm($scope, 0, $pkg, @$arm);
    }
    \ join " ", @script;
  }
}

{
  declare_alias macro_yatt_block => \&macro_block;
  sub macro_block {
    (my MY $trans, my ($scope, $args)) = @_;
    \ $trans->as_block
      ($trans->as_statement_list
       ($trans->generate_body([{}, $scope], $args)));
  }

  declare_alias macro_yatt_my => \&macro_my;
  sub macro_my {
    (my MY $trans, my ($scope, $args)) = @_;
    my @assign;
    for (; $args->readable; $args->next) {
      last unless $args->is_primary_attribute;
      my $name = $args->node_name;
      my $typename;
      ($name, $typename) = @$name if ref $name;
      if ($scope->[0]{$name}) {
	die $trans->node_error($args, "Conflicting varname: %s", $name);
      }
      unless (defined $typename) {
	$typename = $args->next_is_body ? 'html' : 'text';
      }
      my $var = $scope->[0]{$name}
	= $trans->create_var($typename, undef, varname => $name);

      push @assign, [$var, $args->node_size
		     ? $var->gen_assignable_node($trans, $scope, $args)
		     : ()];
    }

    if ($args->readable) {
      my $var = $assign[-1][0];
      $assign[-1][1] ||= $var->gen_assignable_node($trans, $scope, $args, 1);
    }

    my @script;
    foreach my $desc (@assign) {
      my ($var, $value) = @$desc;
      my $script = sprintf q{my %s}, $var->as_lvalue;
      $script .= q{ = } . $value if defined $value;
      push @script, \ $script;
    }
    @script;
  }
}

#========================================

sub paren_escape ($) {
  unless (defined $_[0]) {
    confess "Undefined text";
  }
  $_[0] =~ s{([\(\)\\])}{\\$1}g;
  $_[0]
}

sub qparen ($) {
  'q('.paren_escape($_[0]).')'
}

sub qqvalue ($) {
  'q'.qparen($_[0]);
}

sub dots_for_arrows {
  shift;
  return unless defined $_[0];
  $_[0] =~ s{\b\.(?=\w+\()}{->}g;
  $_[0];
}

1;
