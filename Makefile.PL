use ExtUtils::MakeMaker;

WriteMakefile(
    'ABSTRACT_FROM'  => 'lib/HTTP/ProxyAutoConfig.pm',
    'AUTHOR'         => 'Ryan Eatmon <reatmon@mail.com>, Craig MacKenna <craig@animalhead.com>',
    'BUILD_REQUIRES' => {'LWP'           => 5.834,
                         'Test::More'    => 0},
    'LICENSE'        => 'perl',
	'NAME'	         => 'HTTP::ProxyAutoConfig',
    'PREREQ_PM'      => {'Carp'          => 0,
                         'IO::Socket'    => 0,
                         'POSIX'         => 0,
                         'Sys::Hostname' => 0},
	'VERSION_FROM'   => 'lib/HTTP/ProxyAutoConfig.pm',
);
