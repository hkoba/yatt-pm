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
        'perl'       => '5.7.2',
        'version'    => 0,
        'File::Remove' => 0,
        'List::Util' => 0,
        'Test::More' => 0,
	'Test::Differences' => 0,
    },
    pm_files => \%pm_files,
    test_files => Module::Build->rscan_dir('web/cgi-bin/yatt.lib/t', qr{\.t}),
    script_files => {'scripts/yatt-driver.zsh' => 'bin/yatt-driver.zsh'},
    add_to_cleanup      => [ qw(YATT-* *.tmp) ],
);

$builder->create_build_script();
