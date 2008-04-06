#!/usr/bin/perl -w
# -*- mode: perl; coding: utf-8 -*-
use strict;
use warnings FATAL => qw(all);

use FindBin;
use lib "$FindBin::Bin/..";

use YATT::Test;

unless (eval {require WWW::Mechanize}) {
  plan skip_all => 'WWW::Mechanized is not installed.'; exit;
}

my $mech = new WWW::Mechanize(agent => "YATT UnitTest by $ENV{USER}");

# XXX: Hard coded.
# /var/www/html/yatt/cgi-bin
# /var/www/html/yatt/test
unless (-e "/var/www/html/yatt/cgi-bin/yatt.cgi"
	and -d "/var/www/html/yatt/test") {
  plan skip_all => 'yatt.cgi and testapp is not installed.'; exit;
} elsif (not $mech->get("http://localhost/")) {
  plan skip_all => "Can't get http://localhost/"; exit;
} else {
  plan qw(no_plan);
}

my $check = sub {
  my ($url, $is, $title) = @_;
  $title ||= $url;
  ok my $res = $mech->get($url)->is_success, "$title - fetch";
  SKIP: {
     skip "Can't fetch.", 1 unless $res;

     unless (ref $is) {
       is $mech->content, $is, $title;
     } elsif (ref $is eq 'Regexp') {
       like $mech->content, $is, $title;
     } else {
       die "Unknown";
     }
    }
};

{
  $check->("http://localhost/yatt/cgi-bin/yatt.cgi"
	   , "None of PATH_TRANSLATED and PATH_INFO is given.\n"
	   , "yatt.cgi returns default error message");
}

{
  $check->("http://localhost/yatt/test/y1hello.html"
	   , "<h2>Hello</h2>\nRedirected mode.\n"
	   , "hello");
}
