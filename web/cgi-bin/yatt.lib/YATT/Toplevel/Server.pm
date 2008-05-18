package YATT::Toplevel::Server;
use strict;
use warnings FATAL => qw(all);

use base qw(HTTP::Server::Simple::CGI
	    YATT::Toplevel::CGI);

use YATT::Toplevel::CGI qw(*PATH_INFO rootname capture);
use YATT::Util::Taint;

sub default_port () { 8766 }

sub run_server {
  my ($pack, $dir, %args) = @_;
  my $server = $pack->SUPER::new(delete $args{port} || $pack->default_port);
  $server->{TOP} = $pack->new_config(auto_reload => 1
				     , %args)->create_toplevel($dir);
  $server->SUPER::run;
}

sub handle_request {
  my ($server, $cgi) = @_;
  my $top = $server->{TOP};
  my $file = $cgi->path_info;
  $file .= "index" if $file =~ m{/$};
  $file =~ s{\.html?$}{};
  my ($renderer, $pkg) = $top->registry->get_handler_to(render => $file);
  my $html = capture { $renderer->($pkg) };
  print "HTTP/1.0 200\r\n";
  print $cgi->header;
  print $html;
}

1;
