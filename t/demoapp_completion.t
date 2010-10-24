#!/gsc/bin/perl

use strict;
use warnings;

use Test::More;
use FindBin;

local $ENV{PATH} = $FindBin::Bin . ':' . $ENV{PATH};
my $path = 'demoapp';
plan tests => 9;

ok(-e $FindBin::Bin . '/' . $path, "found the demo program ($path)");
ok(test_completion("$path model build ") > 0, 'results for valid sub-command');
ok(test_completion("$path model buil") > 0, 'results for valid partial sub-command');
ok(test_completion("$path projectx ") == 0, 'no results for bad sub-command');
ok(test_completion("$path project list --filter name=foo ") > 0, 'results for valid option-space-argument');
ok(test_completion("$path project list --filter=name=foo ") > 0, 'results for valid option-equals-argument');
ok(test_completion("$path model --help foo ") == 0, 'no results for invalid argument');
ok(test_completion("$path model --help foo") == 0, 'no results for non-argument option');
ok(test_completion("$path project list --filter name=foo") == 0, 'no results for option argument');

sub test_completion {
    my $COMP_LINE = shift;
    my $COMP_POINT = length($COMP_LINE);
    my $command = (split(' ', $COMP_LINE))[0];
    my @results = split("\n", `COMP_LINE='$COMP_LINE' COMP_POINT=$COMP_POINT $command`);
    print "Found " . scalar(@results) . " results for '$COMP_LINE': " . join(', ', @results) . ".\n";
    return scalar(@results);
}
