package YATT::Toplevel::Server;
use strict;
use warnings FATAL => qw(all);

use base qw(HTTP::Server::Simple::CGI
	    YATT::Toplevel::CGI);

use YATT::Toplevel::CGI qw(*PATH_INFO rootname capture);
use YATT::Util::Taint;

sub default_port () { 8765 }

sub run_server {
  my ($pack, $port, @args) = @_;
  my $server = $pack->SUPER::new($port || $pack->default_port);
  my $loader = $pack->loader_for_script($0);
  $server->{TRANSLATOR} = $pack->new_translator($loader, refresh => 1
						, @args);
  $server->SUPER::run;
}

sub handle_request {
  my ($server, $cgi) = @_;
  my $top = $server->{TRANSLATOR};
  my $file = $cgi->path_info;
  $file .= "index" if $file =~ m{/$};
  $file =~ s{\.html?$}{};
  my $renderer = $top->get_handler_to(render => $file);
  my $html = capture { $renderer->() };
  print "HTTP/1.0 200\r\n";
  print $cgi->header;
  print $html;
}

1;
