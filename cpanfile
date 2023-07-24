# -*- coding: utf-8; mode: perl -*-
use strict;

requires perl => '5.7.2'; # for sprintf reordering.

requires version => 0.77;

requires 'File::Remove'; # Should be replaced to File::Path.
requires 'List::Util';
requires 'Test::More';
requires 'Test::Differences';
requires 'Test::WWW::Mechanize::CGI';

requires 'FCGI';
requires 'CGI::Fast';
requires 'DBD::SQLite';
