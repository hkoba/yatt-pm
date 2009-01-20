# -*- mode: perl; coding: utf-8 -*-
package YATT::Toplevel::CGI;
use strict;
use warnings FATAL => qw(all);

BEGIN {require Exporter; *import = \&Exporter::import}

use base qw(File::Spec);
use File::Basename;
use Carp;
use UNIVERSAL;

#----------------------------------------
use YATT;
use YATT::Types -alias =>
  [MY => __PACKAGE__
   , Translator => 'YATT::Translator::Perl'];

require YATT::Inc;
use YATT::Util;
use YATT::Util::Finalizer;
use YATT::Util::Taint qw(untaint_any);
use YATT::Util::Symbol;
use YATT::Util::CmdLine;

use YATT::Exception;

#----------------------------------------
use base qw(YATT::Class::Configurable);
use YATT::Types -base => __PACKAGE__
  , [Config => [qw(^cf_registry
		   cf_docs cf_tmpl
		   cf_charset
		   cf_debug_allowed_ip
		   cf_translator_param
		   cf_user_config
		   cf_no_header
		   cf_allow_unknown_config
		   cf_auto_reload
		   cf_no_chdir
		 )
		, ['^cf_app_prefix' => 'YATT']
		, ['^cf_find_root_upward' => 2]
	       ]]
  , qw(:export_alias);

Config->define(create => \&create_toplevel);

#----------------------------------------

use vars map {'$'.$_} our @env_vars
  = qw(DOCUMENT_ROOT
       PATH_INFO
       PATH_TRANSLATED
       REDIRECT_REDIRECT_STATUS
       REDIRECT_STATUS
       REDIRECT_URL
       REQUEST_URI
       SCRIPT_FILENAME
     );
push our @EXPORT, (qw(&use_env_vars
		  &rootname
		  &capture
		  &new_config
		), map {'*'.$_} our @env_vars);

our Config $CONFIG;
our ($CGI, $SESSION, %COOKIE, %HEADER, $RANDOM_LIST, $RANDOM_INDEX);
sub rc_global () { qw(CONFIG CGI SESSION HEADER COOKIE
		      RANDOM_LIST RANDOM_INDEX) }
push our @EXPORT_OK, (@EXPORT, map {'*'.$_} rc_global);

sub ROOT_CONFIG () {'.htyattroot'}

#----------------------------------------
# run -> run_zzz -> dispatch(handler) -> dispatch_zzz(handler) -> handler

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
  my $cgi = $pack->new_cgi(shift);

  local $CONFIG = my Config $config = $pack->new_config(shift);

  my ($root, $file, $error, $param);
  if (catch {
    ($pack, $root, $cgi, $file, $param)
      = $pack->prepare_dispatch($cgi, $config);
    } \ $error or catch {
      $pack->dispatch($root, $cgi, $file, $param);
    } \ $error and not is_normal_end($error)) {
    $pack->dispatch_error($root, $error
			  , {phase => 'action', target => $file});
  }
}

sub create_toplevel {
  (my Config $config, my ($dir)) = splice @_, 0, 2;

  $dir ||= '.';

  $config->configure(@_) if @_;

  $config->try_load_config($dir);

  my @loader = (DIR => $config->{cf_docs});

  push @loader, LIB => $config->{cf_tmpl} if $config->{cf_tmpl};

  $config->{cf_registry} = $config->new_translator
    (\@loader, $config->translator_param);

  $config;
}

sub prepare_dispatch {
  (my ($pack, $cgi), my Config $config) = @_;
  my ($rootdir, $file, $loader, $param) = do {
    if (not $config->{cf_registry} and $config->{cf_docs}) {
      # $config->try_load_config($config->{cf_docs});
      ($config->{cf_docs}, $cgi->path_info
       , [DIR => $config->{cf_docs}]);
    } elsif ($REDIRECT_STATUS) {
      # 404 Not found handling
      my $target = $PATH_TRANSLATED || $DOCUMENT_ROOT . $REDIRECT_URL;
      ($pack->param_for_redirect($target
				 , $SCRIPT_FILENAME || $0, $config
				 , $REDIRECT_STATUS == 404
				));
    } elsif ($PATH_INFO and $SCRIPT_FILENAME) {
      (untaint_any(dirname($SCRIPT_FILENAME))
       , untaint_any($PATH_INFO)
       , $pack->loader_for_script($SCRIPT_FILENAME, $config));
    } else {
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
      # XXX: ミス時に効率悪い。substr して eq に書き直すべき。
      if (index($PATH_TRANSLATED, $rootdir) == 0) {
	$PATH_INFO = substr($PATH_TRANSLATED, length($rootdir));
      }
    }
  }

  $cgi->charset($config->{cf_charset} || 'utf-8');

  my $instpkg = $pack->prepare_export($config);

  my $root = $config->{cf_registry} ||= $instpkg->new_translator
    ($loader, $config->translator_param
     , debug_translator => $ENV{DEBUG});

  ($instpkg, $root, $cgi, $file, $param);
}

sub prepare_export {
  my ($pack, $config, $instpkg) = @_;
  $instpkg ||= $config && $config->app_prefix || 'main';

  $pack->add_isa($instpkg, $pack);
  foreach my $name ($pack->rc_global) {
    *{globref($instpkg, $name)} = *{globref(MY, $name)};
  }
  $instpkg
}

sub run_template {
  my ($pack, $file, $cgi, $config) = @_;

  if (defined $file and -r $file) {
    ($PATH_INFO, $REDIRECT_STATUS, $PATH_TRANSLATED) = ('', 200, $file);
    die "really?" unless $ENV{REDIRECT_STATUS} == 200;
    die "really?" unless $ENV{PATH_TRANSLATED} eq $file;
  }

  $pack->run_cgi($cgi, $config);
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
  my @elpath = $root->parse_elempath($top->canonicalize_html_filename($file));
  my ($found, $renderer, $pkg, $widget);

  if (catch {
    $found = ($renderer, $pkg, $widget)
      = $root->lookup_handler_to(render => @elpath);
  } \ my $error) {
    $top->dispatch_error($root, $error
			 , {phase => 'get_handler', target => $file});
  } elsif (not $found) {
    # XXX: これも。
    $top->dispatch_not_found($root, $file, @param);
  } else {
    unless ($CONFIG->{cf_no_chdir}) {
      # XXX: これもエラー処理を
      my $dir = untaint_any(dirname($widget->filename));
      chdir($dir);
    }
    if (not defined $param[0] and $widget->public) {
      $param[0] = $widget->reorder_cgi_params($cgi);
    }
    if (my $handler = $pkg->can('dispatch_action')) {
      $handler->($top, $root, $renderer, $pkg, @param);
    } else {
      $top->dispatch_action($root, $renderer, $pkg, @param);
    }
  }
}

sub dispatch_not_found {
  my ($top, $root, $file) = @_;
  my $ERR = \*STDOUT;

  print $ERR "\n\nNot found: $file";
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
    print $ERR $CGI ? $CGI->header : "\n\n";
    print $ERR $error;
    $top->printenv_html($info, id => 'error_info') if $info;
    $top->printenv_html;
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
  # XXX: $CONFIG->{cf_no_header}
  my $html = capture { $action->($pkg, @param) };
  # XXX: SESSION, COOKIE, HEADER...
  print $CGI->header;
  print $html;
  $top->bye;
}

sub plain_error {
  my ($pack, $cgi, $message) = @_;
  print $cgi->header if $cgi;
  print $message;
  $pack->printenv_html;
  $pack->plain_exit($cgi ? 0 : 1);
}

sub plain_exit {
  my ($pack, $exit_code) = @_;
  exit $exit_code;
}

sub printenv_html {
  my ($pack, $env, %opts) = @_;
  $opts{id} ||= 'printenv';
  my $ERR = \*STDOUT;
  $env ||= \%ENV;
  print $ERR "<table id='$opts{id}'>\n";
  foreach my $k (sort keys %$env) {
    print $ERR "<tr><td>", $k, "</td><td>", $env->{$k}, "</td></tr>\n";
  }
  print $ERR "</table>\n";
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

sub upward_find_file {
  my ($pack, $file, $level) = @_;
  my @path = $pack->splitdir($pack->rel2abs($file));
  my $limit = defined $level ? @path - $level : 0;
  my ($dir);
  for (my $i = $#path - 1; $i >= $limit; $i--) {
    $dir = join "/", @path[0..$i];
    $file = "$dir/" . $pack->ROOT_CONFIG;
    next unless -r $file;
    return wantarray ? ($dir, $file) : $file;
  }

  return
}

sub try_load_config {
  (my Config $config, my ($file)) = @_;

  my $dir;
  unless (defined $file and -r $file) {
    die "No such file or directory! "
      . (defined $file ? $file : "(undef)") . "\n";
  } elsif (-f $file) {
    # ok
    $file = $config->rel2abs($file);
    $dir = dirname($file);
  } elsif (! -d $file) {
    die "Unsupported file type! $file";
  } elsif (-r (my $found = "$file/" . $config->ROOT_CONFIG)) {
    ($dir, $file) = ($file, $found);
  } elsif ($config->find_root_upward
	   and my @found = $config->upward_find_file
	   ($file, $config->find_root_upward)) {
    ($dir, $file) = @found;
  } else {
    $dir = $file;
  }

  $config->configure(docs => $dir);
  if (-d (my $libdir = "$dir/lib")) {
    unshift @INC, $libdir;
  }

  return unless -r $file;

  my @param = do {
    require YATT::XHF;
    my $parser = new YATT::XHF(filename => $file);
    $parser->read_as('pairlist');
  };

  $config->classify_config_param(@param);
}

sub trim_trailing_pathinfo {
  my ($pack, $strref, @prefix) = @_;
  @prefix = ('') unless @prefix;
  my @dirs = $pack->splitdir($$strref);
  my @found;
  while (@dirs and -e join("/", @prefix, @found, $dirs[0])) {
    push @found, shift @dirs;
  }
  $$strref = join("/", @found);
  return unless @dirs;
  join("/", @dirs);
}

sub param_for_redirect {
  (my ($pack, $path_translated, $script_filename)
   , my Config $cfobj, my $not_found) = @_;
  my $driver = untaint_any(rootname($script_filename));

  my @params;
  if (not $not_found and not -e $path_translated) {
    # not_found でもないのに、 path_translated が not exists であるケース
    # == trailing path_info が有るケース。
    push @params, $pack->trim_trailing_pathinfo(\$path_translated);
  }

  # This should set $cfobj->{cf_docs}
  unless ($cfobj->{cf_registry}) {
    # .htyattroot の読み込みは、registry 作成前の一度で十分。
    $cfobj->try_load_config(dirname(untaint_any($path_translated)));
  }

  my $target = substr($path_translated
		      , length($cfobj->{cf_docs}));

  my @loader = (DIR => $cfobj->{cf_docs}
		, $pack->tmpl_for_driver($driver));

  return ($cfobj->{cf_docs}, $target, \@loader, @params ? \@params : ());
}

#========================================

sub cgi_classes () { qw(CGI::Simple CGI) }

sub new_cgi {
  my ($pack, $oldcgi) = @_;
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
  if (UNIVERSAL::isa($oldcgi, $class)) {
    $class->new($pack->extract_cgi_params($oldcgi));
  } else {
    $class->new(defined $oldcgi ? $oldcgi : ());
  }
}

sub new_config {
  my $pack = shift;
  my $config = @_ == 1 ? shift : \@_;
  return $config if defined $config
    and ref $config and UNIVERSAL::isa($config, Config);

  if (ref $pack or not UNIVERSAL::isa($pack, Config)) {
    $pack = $pack->Config;
  }

  $pack->new(do {
    unless (defined $config) {
      ()
    } elsif (ref $config eq 'ARRAY') {
      @$config
    } elsif (ref $config eq 'HASH') {
      %$config
    } else {
      $pack->plain_error(undef, <<END);
Invalid configuration parameter: $config
END
    }
  });
}

sub classify_config_param {
  my Config $config = shift;
  my $config_keys = $config->fields_hash;
  my $trans_keys = $config->load_type('Translator')->fields_hash_of_class;
  my (@mine, @trans, @unknown);
  while (my ($name, $value) = splice @_, 0, 2) {
    if ($config_keys->{"cf_$name"}) {
      push @mine, $name, $value;
    }
    if ($trans_keys->{"cf_$name"}) {
      push @trans, [$name, $value];
    } else {
      push @unknown, [$name, $value];
    }
  }
  $config->configure(@mine) if @mine;
  foreach my $name ($config->configkeys) {
    if ($trans_keys->{"cf_$name"}
	and defined (my $value = $config->{"cf_$name"})) {
      push @trans, [$name, $value];
    }
  }
  $config->{cf_translator_param}{$_->[0]} = $_->[1] for @trans;
  if (@unknown and $config->{cf_allow_unknown_config}) {
    $config->{cf_user_config}{$_->[0]} = $_->[1] for @unknown;
  }
  $config;
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
  my ($self, $loader) = splice @_, 0, 2;
  my $pack = ref $self || $self;
  $pack->call_type(Translator => new =>
		   app_prefix => $pack
		   , default_base_class => $pack
		   , rc_global => [$pack->rc_global]
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

sub set_random_list {
  my ($this, $random) = @_;
  if (defined $random) {
    $RANDOM_LIST = ref $random ? $random : [split " ", $random];
    $RANDOM_INDEX = 0;
  } else {
    undef $RANDOM_LIST;
    undef $RANDOM_INDEX;
  }
}

sub entity_rand {
  my ($this, $scalar) = @_;
  $scalar ||= 1;
  if ($RANDOM_LIST) {
    my $val = $RANDOM_LIST->[$RANDOM_INDEX++ % @$RANDOM_LIST];
    $val * $scalar;
  } else {
    rand $scalar;
  }
}

sub entity_randomize {
  my ($this) = shift;
  my $sub = $this->can('entity_rand');
  my @result;
  push @result, splice @_, $sub->($this, scalar @_), 1 while @_;
  wantarray ? @result : \@result;
}

sub entity_breakpoint {
  &YATT::breakpoint();
}

sub entity_concat {
  my $this = shift;
  join '', @_;
}

sub entity_join {
  my ($this, $sep) = splice @_, 0, 2;
  join $sep, grep {defined $_ && $_ ne ''} @_;
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
  my $copy = shift;
  $copy =~ s{\.(y?html?|yatt?)$}{};
  $copy;
}

sub widget_path_in {
  my ($pack, $rootdir, $file) = @_;
  unless (index($file, $rootdir) == 0) {
    $pack->plain_error
      (undef, "Requested file $file is not in rootdir $rootdir");
  }

  my @elempath
    = split '/', $pack->canonicalize_html_filename
      (substr($file, length($rootdir)));
  shift @elempath if defined $elempath[0] and $elempath[0] eq '';

  @elempath;
}

sub YATT::Toplevel::CGI::Config::translator_param {
  my Config $config = shift;
  # print "translator_param: ", terse_dump($config), "\n";
  map($_ ? (ref $_ eq 'ARRAY' ? @$_ : %$_) : ()
      , $config->{cf_translator_param})
}

# Config に
sub is_debug_allowed {
  (my Config $config, my ($cgi)) = @_;
  
}

#========================================
package YATT::Toplevel::CGI::Batch; use YATT::Inc;
use base qw(YATT::Toplevel::CGI);
use YATT::Util qw(catch);

sub run_files {
  my $pack = shift;
  my ($method, $flag, @opts) = $pack->parse_opts(\@_);
  my $config = $pack->new_config(\@opts);
  $pack->parse_params(\@_, \ my %param);

  foreach my $file (@_) {
    print "=== $file ===\n" if $ENV{VERBOSE};
    if (catch {
      $pack->run_template($pack->rel2abs($file), \%param, $config);
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
