use strict;
use warnings;
use Module::Build;

my %pm_files = (
  map {my ($std) = $_; $std =~ s{^web/cgi-bin/yatt.lib/}{lib/}; $_ => $std}
  @{Module::Build->rscan_dir('web/cgi-bin/yatt.lib', qr{\.pm})}
);

my $builder = Module::Build->new(
    module_name         => 'YATT',
    license             => 'perl',
    dist_author         => '"KOBAYASI, Hiroaki" <hkoba@cpan.org>',
    dist_version_from   => 'web/cgi-bin/yatt.lib/YATT.pm',
    requires => {
        'Test::More' => 0,
	'Test::Differences' => 0,
        'version'    => 0,
    },
	pm_files => \%pm_files,
	test_files => Module::Build->rscan_dir('web/cgi-bin/yatt.lib/t', qr{\.t}),
    add_to_cleanup      => [ qw(YATT-* *.tmp) ],
);

$builder->create_build_script();
