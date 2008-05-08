# -*- mode: perl; coding: utf-8 -*-
package YATT::Test;
use strict;
use warnings FATAL => qw(all);
use base qw(Test::More);

use File::Basename;
use Data::Dumper;
use Carp;

use YATT;
use YATT::Util qw(rootname catch checked_eval default defined_fmt);
use YATT::Util::Symbol;
use YATT::Util::Finalizer;
use YATT::Util::DirTreeBuilder qw(tmpbuilder);
use YATT::Util::DictOrder;

#========================================

our @EXPORT = qw(ok is isnt like is_deeply skip fail plan
		 require_ok isa_ok
		 basename

		 is_rendered raises is_can run
		 capture rootname checked_eval default defined_fmt
		 tmpbuilder
		 dumper

		 xhf_test
		 *TRANS
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
  my $error;
  local $SIG{__DIE__} = sub {$error = @_ > 1 ? [@_] : shift};
  local $SIG{__WARN__} = sub {$error = @_ > 1 ? [@_] : shift};
  my ($sub, $pkg) = eval {
    &YATT::break_translator;
    $trans->get_handler_to(render => @$path)
  };
  Test::More::is $error, undef, "$title - compiled.";
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
  my $result = eval {capture {$trans->$method(@args)}};
  Test::More::like $@, $cmp, $title;
  $result;
}

#----------------------------------------

sub dumper {
  join "\n", map {
    Data::Dumper->new([$_])->Terse(1)->Indent(0)->Dump;
  } @_;
}

#----------------------------------------

use YATT::Types [TestDesc => [qw(cf_FILE realfile
				 ntests
				 cf_TITLE num cf_TAG
				 cf_BREAK
				 cf_SKIP
				 cf_WIDGET
				 cf_IN cf_PARAM cf_OUT cf_ERROR)]];

sub ntests {
  my $ntests = 0;
  foreach my $section (@_) {
    foreach my TestDesc $test (@{$section}[1 .. $#$section]) {
      $ntests += $test->{ntests};
    }
  }
  $ntests;
}

our $TRANS = 'YATT::Translator::Perl';

sub xhf_test {
  my $TMPDIR = tmpbuilder(shift);

  unless (@_) {
    croak "Source is missing."
  } elsif (@_ == 1 and -d $_[0]) {
    my $srcdir = shift;
    @_ = dict_sort <$srcdir/*.xhf>;
  }

  require YATT::XHF;

  my @sections;
  foreach my $testfile (@_) {
    my $parser = new YATT::XHF(filename => $testfile);
    my TestDesc $prev;
    my ($n, @test, %uniq) = (0);
    while (my $rec = $parser->read_as_hash) {
      my TestDesc $test = TestDesc->new(%$rec);

      push @test, $test;
      $test->{ntests} = do {
	if ($test->{cf_OUT}) {
	  2
	} elsif ($test->{cf_ERROR}) {
	  1
	} else {
	  0
	}
      };

      $test->{cf_FILE} ||= $prev && $prev->{cf_FILE}
	&& $prev->{cf_FILE} =~ m{%d} ? $prev->{cf_FILE} : undef;

      if ($test->{cf_IN}) {
	$test->{realfile} = sprintf($test->{cf_FILE} ||= "doc/f%d.html", $n);
	$test->{cf_WIDGET} ||= do {
	  my $widget = $test->{realfile};
	  $widget =~ s{^doc/}{};
	  $widget =~ s{\.\w+$}{};
	  $widget =~ s{/}{:}g;
	  $widget;
	};
      }

      if ($test->{cf_OUT}) {
	$test->{cf_WIDGET} ||= $prev && $prev->{cf_WIDGET};
	if (not $test->{cf_TITLE} and $prev) {
	  $test->{num} = default($prev->{num}) + 1;
	  $test->{cf_TITLE} = $prev->{cf_TITLE};
	}
      }
      $prev = $test;
    } continue {
      $n++;
    }

    push @sections, [$testfile => @test];
  }

  Test::More::plan(tests => 1 + ntests(@sections));

  require_ok($TRANS);

  my $SECTION = 0;
  foreach my $section (@sections) {
    my ($testfile, @all) = @$section;
    my $builder = $TMPDIR->as_sub;
    my $DIR = $builder->([DIR => "doc"]);

    my @test;
    foreach my TestDesc $test (@all) {
      if ($test->{cf_IN}) {
	die "Conflicting FILE: $test->{realfile}!\n" if -e $test->{realfile};
	$builder->($TMPDIR->path2desc($test->{realfile}, $test->{cf_IN}));
      }
      push @test, $test if $test->{cf_OUT} || $test->{cf_ERROR};
    }

    my @loader = (DIR => "$DIR/doc");
    push @loader, LIB => "$DIR/lib" if -d "$DIR/lib";

    my %config;
    if (-r (my $fn = "$DIR/doc/.htyattroot")) {
      %config = YATT::XHF->new(filename => $fn)->read_as('pairlist');
    }

    &YATT::break_translator;
    my $gen = $TRANS->new
      (loader => \@loader
       , app_prefix => "MyApp$SECTION"
       , debug_translator => $ENV{DEBUG}
       , %config
      );

    foreach my TestDesc $test (@test) {
      unless (defined $test->{cf_TITLE}) {
	die "test title is not defined!" . dumper($test);
      }
      my @widget_path = split /:/, $test->{cf_WIDGET};
      my $title = join("", '[', basename($testfile), '] ', $test->{cf_TITLE}
		      , defined_fmt(' (%d)', $test->{num}, ''));
      my ($param) = map {ref $_ ? $_ : 'main'->checked_eval($_)}
	$test->{cf_PARAM} if $test->{cf_PARAM};
    SKIP: {
	if ($test->{cf_OUT}) {
	  Test::More::skip("($test->{cf_SKIP}) $title", 2)
	      if $test->{cf_SKIP};
	  # XXX: this が undef...
	  &YATT::breakpoint if $test->{cf_BREAK};
	  is_rendered [$gen, \@widget_path, $param]
	    , $test->{cf_OUT}, $title;
	} elsif ($test->{cf_ERROR}) {
	  Test::More::skip("($test->{cf_SKIP}) $title", 1)
	      if $test->{cf_SKIP};
	  &YATT::breakpoint if $test->{cf_BREAK};
	  raises [$gen, call_handler => render => \@widget_path, $param]
	    , qr{$test->{cf_ERROR}}s, $title;
	}
      }
    }
  } continue {
    $SECTION++;
  }
}

1;
