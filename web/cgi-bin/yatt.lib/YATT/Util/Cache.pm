package YATT::Util::Cache;
use strict;
use warnings FATAL => qw(all);
use base qw(Exporter);
our @EXPORT = qw(get_cached);
our @EXPORT_OK = @EXPORT;

use constant CACHE_AGE => 0;
use constant CACHE_BODY => 1;

sub get_cached (@) {
  my ($self, $hash, $path, $builder) = @_;
  my $value = $hash->{$path};
  my $mtime;
  if (not(defined $value)
      or $mtime = -M $path and $mtime < $value->[CACHE_AGE]) {
    $mtime = -M $path unless defined $mtime;
    $value = $hash->{$path} = [$mtime, scalar $builder->($value->[CACHE_BODY])];
  }
  $value->[CACHE_BODY];
}

1;
