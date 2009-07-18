
use warnings FATAL => 'all';
use strict;
use inc::Module::Install;

name    'Getopt-Complete';
license 'perl';
all_from 'lib/Getopt/Complete.pm';

# prereqs
requires 'Getopt::Long';
requires 'Scalar::Util';
requires 'IPC::Open2';
requires 'version';
requires 'Carp';

# things the tests need
build_requires 'Test::More' => '0.86';
build_requires 'App::Prove';

#tests('t/*.t t/*/*.t');

WriteAll();

