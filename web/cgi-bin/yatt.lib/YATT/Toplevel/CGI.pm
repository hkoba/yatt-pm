# -*- mode: perl; coding: utf-8 -*-
package YATT::Toplevel::CGI;
use strict;
use warnings FATAL => qw(all);

use Exporter qw(import);

use base qw(File::Spec);
use File::Basename;
use Carp;
use UNIVERSAL;

#----------------------------------------
use YATT;
use YATT::Types -alias =>
  [MY => __PACKAGE__
   , Translator => 'YATT::Translator::Perl'];

use YATT::Util;
use YATT::Util::Finalizer;
use YATT::Util::Taint qw(untaint_any);
use YATT::Util::Symbol;

use YATT::Exception;

#----------------------------------------

use vars map {'$'.$_} our @env_vars
  = qw(DOCUMENT_ROOT
       PATH_INFO
       SCRIPT_FILENAME
       REDIRECT_STATUS
       PATH_TRANSLATED);
our @EXPORT = (qw(&use_env_vars
		  &rootname
		  &capture
		), map {'*'.$_} our @env_vars);

our ($CGI, $SESSION, %COOKIE, %HEADER);
our @EXPORT_OK = (@EXPORT, qw(*CGI *SESSION *COOKIE *HEADER));

sub ROOT_CONFIG () {'.htyattroot'}

#----------------------------------------
# run -> handle -> ??

# run は環境変数を整えるためのエントリー関数。

sub run {
  my ($pack, $method) = splice @_, 0, 2;
  use_env_vars();
  my $sub = $pack->can("run_$method")
    or croak "Can't find handler for $method";

  &YATT::break_run;
  $sub->($pack, @_);
}

sub run_cgi {
  my $pack = shift;
  my $cgi = do {
    if (@_ == 1 && UNIVERSAL::isa($_, 'CGI')) {
      shift;
    } else {
      $pack->new_cgi(@_);
    }
  };

  my ($rootdir, $file, $loader, %param) = do {
    if ($REDIRECT_STATUS and $PATH_TRANSLATED) {
      ($pack->param_for_redirect($PATH_TRANSLATED
				 , $SCRIPT_FILENAME || $0));
    }
    elsif ($PATH_INFO and $SCRIPT_FILENAME) {
      (untaint_any(dirname($SCRIPT_FILENAME))
       , untaint_any($PATH_INFO)
       , $pack->loader_for_script($SCRIPT_FILENAME));
    }
    else {
      $pack->plain_error($cgi, <<END);
None of PATH_TRANSLATED and PATH_INFO is given.
END
    }
  };

  unless ($loader) {
    $pack->plain_error($cgi, <<END);
Can't find loader.
END
  }

  unless (chdir($rootdir)) {
    $pack->plain_error($cgi, "Can't chdir to $rootdir: $!");
  }

  unless ($PATH_INFO) {
    if ($PATH_TRANSLATED) {
      if (index($PATH_TRANSLATED, $rootdir) == 0) {
	$PATH_INFO = substr($PATH_TRANSLATED, length($rootdir));
      }
    }
  }

  $cgi->charset(delete $param{charset} || 'utf-8');

  my @rc_global = qw(CGI SESSION HEADER COOKIE);

  if (my $instpkg = delete $param{app_prefix}) {
    $pack->add_isa($instpkg, $pack);
    foreach my $name (@rc_global) {
      *{globref($instpkg, $name)} = *{globref(MY, $name)};
    }
    $pack = $instpkg;
  }

  our %ROOT_CACHE;
  my ($root, $error);
  if (catch {
    $root = $ROOT_CACHE{$rootdir} ||= $pack->new_translator
      ($loader, %param
       , rc_global => \@rc_global
       , debug_translator => $ENV{DEBUG})
    } \ $error or catch {
      $pack->dispatch($root, $cgi, $file);
    } \ $error and not is_normal_end($error)) {
    $pack->dispatch_error($root, $error
			  , {phase => 'action', target => $file});
  }
}

sub run_template {
  my ($pack, $file) = splice @_, 0, 2;

  if (defined $file and -r $file) {
    ($PATH_INFO, $REDIRECT_STATUS, $PATH_TRANSLATED) = ('', 200, $file);
    die "really?" unless $ENV{REDIRECT_STATUS} == 200;
    die "really?" unless $ENV{PATH_TRANSLATED} eq $file;
  }

  $pack->run_cgi(@_);
}

#========================================
# *: dispatch_zzz が無事に最後まで処理を終えた場合は bye を呼ぶ。
# *: dispatch_zzz の中では catch はしない。dispatch の外側(run)で catch する。

sub bye {
  die shift->Exception->new(error => '', normal => shift || 1
			    , caller => [caller], @_);
}

sub dispatch {
  my ($top, $root, $cgi, $file, @param) = @_;
  &YATT::break_dispatch;

  local $CGI = $cgi;
  local ($SESSION, %COOKIE, %HEADER);
  my ($renderer, $pkg);

  if (catch {
    ($renderer, $pkg) = $root->get_handler_to
      (render => $top->canonicalize_html_filename($file));
  } \ my $error) {
    $top->dispatch_error($root, $error
			 , {phase => 'get_handler', target => $file});
  } else {
    $top->dispatch_action($root, $renderer, $pkg, @param);
  }
}

# XXX: もう少し改善を。
sub dispatch_error {
  my ($top, $root, $error, $info) = @_;
  my $ERR = \*STDOUT;
  my ($found, $renderer, $pkg, $html);

  unless ($root) {
    print $ERR "\n\nroot_load_error($error)";
  } elsif (catch {
    $found = ($renderer, $pkg) = $root->lookup_handler_to(render => 'error')
  } \ my $load_error) {
    print $ERR "\n\nload_error($load_error), original_error=($error)";
  } elsif (not $found) {
    print $ERR "\n\n$error";
  } elsif (catch {
    $html = capture {$renderer->($pkg, [$error, $info])};
  } \ my Exception $error2) {
    unless (ref $error2) {
      print $ERR "\n\nerror in error page($error2), original_error=($error)";
    } elsif (not UNIVERSAL::isa($error2, Exception)) {
      print $ERR "\n\nUnknown error in error page($error2), original_error=($error)";
    } elsif ($error2->is_normal) {
      # should be ignored
    } else {
      print $ERR "\n\nerror in error page($error2->{cf_error}), original_error=($error)";
    }
  } else {
    print $ERR $CGI ? $CGI->header : "Content-type: text/html\n\n";
    print $ERR $html;
  }

  $top->bye;
}

sub dispatch_action {
  my ($top, $root, $action, $pkg, @param) = @_;
  &YATT::break_handler;
  my $html = capture { $action->($pkg, @param) };
  # XXX: SESSION, COOKIE, HEADER...
  print $CGI->header;
  print $html;
  $top->bye;
}

sub plain_error {
  my ($pack, $cgi, $message) = @_;
  print $cgi->header;
  print $message;
  exit;
}

#========================================

sub loader_for_script {
  my ($pack, $script_filename) = @_;
  my $driver = untaint_any(rootname($script_filename));
  my @loader = (DIR => untaint_any("$driver.docs")
		, $pack->tmpl_for_driver($driver));
  \@loader;
}

sub tmpl_for_driver {
  my ($pack, $rootname) = @_;
  return unless -d (my $dir = "$rootname.tmpl");
  (LIB => $dir);
}

sub param_for_redirect {
  my ($pack, $path_translated, $script_filename) = @_;
  my $driver = untaint_any(rootname($script_filename));
  my @path = $pack->splitdir(untaint_any($path_translated));
  for (my $i = $#path - 1; $i >= 0; $i--) {
    my $dir = join "/", @path[0..$i];
    my $config = "$dir/" . $pack->ROOT_CONFIG;
    next unless -r $config;
    my @param = do {
      require YATT::XHF;
      my $parser = new YATT::XHF(filename => $config);
      $parser->read_as('pairlist');
    };
    # Found.
    my $target = join "/", @path[$i+1 .. $#path];
    my @loader = (DIR => $dir
		  , $pack->tmpl_for_driver($driver));
    return ($dir, $target, \@loader, @param);
  }

  die sprintf "Can't find root config for %s", $path_translated;
}

#========================================

sub cgi_classes () { qw(CGI::Simple CGI) }

sub new_cgi {
  my ($pack) = shift;
  my $class;
  foreach my $c ($pack->cgi_classes) {
    eval qq{require $c};
    unless ($@) {
      $class = $c;
      last;
    }
  }
  unless ($class) {
    die "Can't load any of cgi classes";
  }

  # 1. To make sure passing 'public' parameters only.
  # 2. To avoid CGI::Simple eval()
  if (@_ == 1 and UNIVERSAL::isa($_[0], $class)) {
    $class->new($pack->extract_cgi_params($_[0]));
  } else {
    $class->new(@_);
  }
}

sub extract_cgi_params {
  my ($pack, $cgi) = @_;
  my %param;
  foreach my $name ($cgi->param) {
    my @value = $cgi->param($name);
    if (@value > 1) {
      $param{$name} = \@value;
    } else {
      $param{$name} = $value[0];
    }
  }
  \%param
}

sub new_translator {
  my ($pack, $loader) = splice @_, 0, 2;
  $pack->call_type(Translator => new =>
		   app_prefix => $pack
		   , loader => $loader, @_);
}

sub use_env_vars {
  foreach my $vn (our @env_vars) {
    *{globref(MY, $vn)} = do {
      $ENV{$vn} = '' unless defined $ENV{$vn};
      \ $ENV{$vn};
    };
  }
  $SCRIPT_FILENAME ||= $0;
}

#========================================

sub entity_param {
  my ($this) = shift;
  $CGI->param(@_);
}

#========================================

sub canonicalize_html_filename {
  my $pack = shift;
  $_[0] .= "index" if $_[0] =~ m{/$};
  $_[0] =~ s{\.html?$}{};
  $_[0]
}

#========================================
package YATT::Toplevel::CGI::Batch; use YATT::Inc;
use base qw(YATT::Toplevel::CGI);
use YATT::Util qw(catch);

sub run_files {
  my $pack = shift;
  my ($method, %opts);
  while (@_ and $_[0] =~ /^--(?:([\w\.\-]+)(?:=(.*))?)?/) {
    shift;
    last unless defined $1;
    unless (defined $method) {
      $method = $1;
    } else {
      $opts{$1} = defined $2 ? $2 : 1;
    }
  }

  my %param;
  for (; @_ and $_[0] =~ /^([^=]+)=(.*)/; shift) {
    $param{$1} = $2;
  }

  require File::Spec; import File::Spec;

  foreach my $file (@_) {
    print "=== $file ===\n" if $ENV{VERBOSE};
    if (catch {
      $pack->run_template(File::Spec->rel2abs($file), \%param);
    } \ my $error) {
      print STDERR $error;
    }
    print "\n" if $ENV{VERBOSE};
  }
}

sub dispatch_action {
  my ($top, $root, $action, $pkg, @param) = @_;
  &YATT::break_handler;
  $action->($pkg, @param);
  $top->bye;
}

1;
