package YATT::Util::CmdLine;
use strict;
use warnings FATAL => qw(all);

use Exporter qw(import);

our @EXPORT_OK = qw(parse_opts parse_params);
our @EXPORT = @EXPORT_OK;

sub parse_opts {
  my ($pack, $list, $result) = @_;
  unless (defined $result) {
    $result = wantarray ? [] : {};
  }
  while (@$list
	 and my ($n, $v) = $list->[0] =~ /^--(?:([\w\.\-]+)(?:=(.*))?)?/) {
    shift @$list;
    last unless defined $n;
    $v = 1 unless defined $v;
    if (ref $result eq 'HASH') {
      $result->{$n} = $v;
    } else {
      push @$result, $n, $v;
    }
  }
  $result;
}

sub parse_params {
  my ($pack, $list, $hash) = @_;
  $hash = {} unless defined $hash;
  for (; @$list and $list->[0] =~ /^([^=]+)=(.*)/; shift @$list) {
    $hash->{$1} = $2;
  }
  $hash;
}

1;
