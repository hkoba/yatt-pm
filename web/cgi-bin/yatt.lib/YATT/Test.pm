package YATT::Test;
use strict;
use warnings FATAL => qw(all);
use base qw(Test::More);

use File::Basename;
use Data::Dumper;

use YATT;
use YATT::Util qw(rootname catch checked_eval default defined_fmt);
use YATT::Util::Symbol;
use YATT::Util::Finalizer;
use YATT::Util::DirTreeBuilder qw(tmpbuilder);

#========================================

our @EXPORT = qw(ok is isnt like is_deeply skip fail plan
		 require_ok isa_ok
		 basename

		 is_rendered raises is_can run
		 capture rootname checked_eval default defined_fmt
		 tmpbuilder
		 dumper
	       );
foreach my $name (@EXPORT) {
  my $glob = globref(__PACKAGE__, $name);
  unless (*{$glob}{CODE}) {
    *$glob = \&{globref("Test::More", $name)};
  }
}

*eq_or_diff = do {
  if (catch {require Test::Differences} \ my $error) {
    \&Test::More::is;
  } else {
    \&Test::Differences::eq_or_diff;
  }
};

push @EXPORT, qw(eq_or_diff);

our @EXPORT_OK = @EXPORT;

#========================================

sub run {
  my ($testname, $sub) = @_;
  my $res = eval { $sub->() };
  Test::More::is $@, '', "$testname doesn't raise error";
  $res
}

sub is_can ($$$) {
  my ($desc, $cmp, $title) = @_;
  my ($obj, $method, @args) = @$desc;
  my $sub = $obj->can($method);
  Test::More::ok defined $sub, "$title - can";
  if ($sub) {
    Test::More::is scalar($sub->($obj, @args)), $cmp, $title;
  } else {
    Test::More::fail "skipped because method '$method' not found.";
  }
}

sub is_rendered ($$$) {
  my ($desc, $cmp, $title) = @_;
  my ($trans, $path, @args) = @$desc;
  my ($sub, $pkg) = eval {
    &YATT::break_translator;
    $trans->get_handler_to(render => @$path)
  };
  my $error = $@;
  Test::More::is $error, '', "$title - compiled.";
  if (!$error && $sub) {
    my $out = capture {
      &YATT::break_handler;
      $sub->($pkg, @args);
    };
    eq_or_diff($out, $cmp, $title);
  } else {
    Test::More::fail "skipped. $title";
  }
}

sub raises ($$$) {
  my ($desc, $cmp, $title) = @_;
  my ($trans, $method, @args) = @$desc;
  my $result = eval {$trans->$method(@args)};
  Test::More::like $@, $cmp, $title;
  $result;
}

#----------------------------------------

sub dumper {
  join "\n", map {
    Data::Dumper->new([$_])->Terse(1)->Indent(0)->Dump;
  } @_;
}

1;
