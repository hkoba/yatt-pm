#!/usr/bin/perl -w
# -*- mode: perl; coding: utf-8 -*-
use strict;
use warnings FATAL => qw(all);
use FindBin;
use lib "$FindBin::Bin/..";

use List::Util qw(reduce);

#========================================
use YATT::Test;

#========================================
my $TRANS = 'YATT::Translator::Perl';
my $ROOTNAME = rootname($0);
my $TMPDIR = tmpbuilder("$ROOTNAME.tmp");

use YATT::Types [TestDesc => [qw(cf_FILE realfile
				 ntests
				 cf_TITLE num cf_TAG
				 cf_BREAK
				 cf_SKIP
				 cf_WIDGET
				 cf_IN cf_PARAM cf_OUT cf_ERROR)]];
{
  require YATT::XHF;
  @ARGV = sort <$ROOTNAME/*.xhf> unless @ARGV;

  my @sections;
  foreach my $testfile (@ARGV) {
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

  #  my $num_tests = 0; $num_tests += @{$$_[2]} for @sections;

  plan tests => 1 + reduce {
    our ($a, $b);
    $a + reduce {
      our TestDesc $b;
      $a + $b->{ntests};
    } 0, @{$b}[1 .. $#$b];
  } 0, @sections;

  require_ok($TRANS);

  my $SECTION = 0;
  foreach my $section (@sections) {
    my ($testfile, @all) = @$section;
    my $builder = $TMPDIR->as_sub;
    my $DIR = $builder->([DIR => "doc"], [DIR => "lib"]);

    my @test;
    foreach my TestDesc $test (@all) {
      if ($test->{cf_IN}) {
	die "Conflicting FILE: $test->{realfile}!\n" if -e $test->{realfile};
	$builder->($TMPDIR->path2desc($test->{realfile}, $test->{cf_IN}));
      }
      push @test, $test if $test->{cf_OUT} || $test->{cf_ERROR};
    }

    my $gen = YATT::Translator::Perl->new
      (loader => [DIR => "$DIR/doc", LIB => "$DIR/lib"]
       , app_prefix => "MyApp$SECTION"
       , debug_translator => $ENV{DEBUG}
      );

    foreach my TestDesc $test (@test) {
      unless (defined $test->{cf_TITLE}) {
	die "test title is not defined!" . dumper($test);
      }
      my @widget_path = split /:/, $test->{cf_WIDGET};
      my $title = join("", '[', basename($testfile), '] ', $test->{cf_TITLE}
		      , defined_fmt(' (%d)', $test->{num}, ''));
      if ($test->{cf_OUT}) {
	my ($param) = map {ref $_ ? $_ : 'main'->checked_eval($_)}
	  $test->{cf_PARAM} if $test->{cf_PARAM};
	# XXX: this が undef...
	&YATT::breakpoint if $test->{cf_BREAK};
	is_rendered [$gen, \@widget_path, $param]
	  , $test->{cf_OUT}, $title;
      } elsif ($test->{cf_ERROR}) {
      SKIP: {
	  skip $test->{cf_SKIP}, 1 if $test->{cf_SKIP};
	  &YATT::breakpoint if $test->{cf_BREAK};
	  raises [$gen, call_handler => render => \@widget_path]
	    , qr{$test->{cf_ERROR}}s, $title;
	}
      }
    }
  } continue {
    $SECTION++;
  }
}

