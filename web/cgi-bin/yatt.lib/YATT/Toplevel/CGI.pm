package YATT::Toplevel::CGI;
use strict;
use warnings FATAL => qw(all);

use Exporter qw(import);

use base qw(File::Spec);
use File::Basename;
use Carp;

#----------------------------------------
use YATT::Types -alias =>
  [MY => __PACKAGE__
   , Translator => 'YATT::Translator::Perl'];

use YATT::Util;
use YATT::Util::Finalizer;
use YATT::Util::Taint qw(untaint_any);
use YATT::Util::Symbol;

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

#----------------------------------------

sub run {
  my ($pack, $method) = splice @_, 0, 2;
  use_env_vars();
  my $sub = $pack->can("run_$method")
    or croak "Can't find handler for $method";

  &YATT::break_run;
  $sub->($pack, @_);
}

# run -> handle -> ??

sub ROOT_CONFIG () {'.htyattroot'}

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

  $cgi->charset(delete $param{charset} || 'utf-8');

  my @rc_global = qw(CGI SESSION HEADER COOKIE);

  if (my $instpkg = delete $param{app_prefix}) {
    $pack->add_isa($instpkg, $pack);
    foreach my $name (@rc_global) {
      *{globref($instpkg, $name)} = *{globref($pack, $name)};
    }
    $pack = $instpkg;
  }

  my $root = $pack->new_translator
    ($loader, %param
     , rc_global => \@rc_global
     , debug_translator => $ENV{DEBUG});

  &YATT::break_dispatch;
  $pack->dispatch($root, $cgi, $file);
}

sub canonicalize_html_filename {
  my $pack = shift;
  $_[0] .= "index" if $_[0] =~ m{/$};
  $_[0] =~ s{\.html?$}{};
  $_[0]
}

sub dispatch {
  my ($top, $root, $cgi, $file, @param) = @_;

  local $CGI = $cgi;
  local ($SESSION, %COOKIE, %HEADER);

  # XXX: Can raise error.
  my ($renderer, $pkg) = $root->get_handler_to
    (render => $top->canonicalize_html_filename($file));

  $top->dispatch_action($root, $renderer, $pkg, @param);
}

sub dispatch_action {
  my ($top, $root, $action, $pkg, @param) = @_;
  &YATT::break_handler;
  my $html = capture { $action->($pkg, @param) };
  print $CGI->header;
  print $html;
}

sub plain_error {
  my ($pack, $cgi, $message) = @_;
  print $cgi->header;
  print $message;
  exit;
}

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

sub new_cgi {
  my ($pack) = shift;
  require CGI;
  CGI->new(@_);
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
      if (defined $ENV{$vn}) {
	\ $ENV{$vn};
      } else {
	\ my $var;
      }
    };
  }
  $SCRIPT_FILENAME ||= $0;
}

1;
