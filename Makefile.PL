use strict;
use warnings;
use ExtUtils::MakeMaker;

WriteMakefile(
    NAME                => 'Getopt::Complete',
    AUTHOR              => 'Scott Smith <sakoht@cpan.org>',
    VERSION_FROM        => 'lib/Getopt/Complete.pm',
    ABSTRACT_FROM       => 'lib/Getopt/Complete.pm',
    PL_FILES            => {},
    PREREQ_PM => {
        'Test::More' => 0,
    },
    dist                => { COMPRESS => 'gzip -9f', SUFFIX => 'gz', },
    clean               => { FILES => 'Getopt-Complete-*' },
);
