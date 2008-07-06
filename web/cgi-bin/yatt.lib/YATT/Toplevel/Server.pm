package YATT::Toplevel::Server;
use strict;
use warnings FATAL => qw(all);

use YATT::Toplevel::CGI qw(*PATH_INFO rootname capture Config);

use base qw(HTTP::Server::Simple::CGI
	    YATT::Toplevel::CGI);

use Carp;

use YATT::Util::Taint;
use YATT::Util;

sub default_port () { 8766 }

sub run_server {
  my ($pack, $dir, %args) = @_;
  my $server = $pack->SUPER::new(delete $args{port} || $pack->default_port);
  my Config $top = $pack->new_config(auto_reload => 1
				     , find_root_upward => 0
				     , %args)->create_toplevel($dir);
  $server->{TOP} = $top;
  unless (chdir($top->{cf_docs})) {
    die "Can't chdir to docs: $top->{cf_docs}";
  }
  $server->SUPER::run;
}

sub handle_request {
  my ($server, $cgi) = @_;
  my Config $top = $server->{TOP};
  $cgi->charset($top->{cf_charset} || 'utf-8');

  my $file = $cgi->path_info;
  my @args;
  unless (-e "$top->{cf_docs}$file") {
    my @dirs = $top->splitdir($file);
    my @found;
    while (@dirs and -e join("/", $top->{cf_docs}, @found, $dirs[0])) {
      push @found, shift @dirs;
    }
    push @args, join("/", @dirs) if @dirs;
    $file = join("/", @found);
  }
  my ($renderer, $pkg, $widget);
  my ($html, $error);

  local $SIG{__DIE__} = sub {
    print STDERR Carp::longmess('error while request handling: ', @_);
    die @_;
  };

  if (catch {
    ($renderer, $pkg, $widget) = $top->registry->get_handler_to
      (render => $top->canonicalize_html_filename($file));
  } \ $error or catch {
    $html = capture {
      $renderer->($pkg, $widget->reorder_cgi_params($cgi, \@args))
    }
  } \ $error) {
    print "HTTP/1.0 500\r\n\r\n";
    print $error;
  } else {
    print "HTTP/1.0 200\r\n";
    print $cgi->header;
    print $html;
  }
}

1;
