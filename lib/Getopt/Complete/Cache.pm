package Getopt::Complete::Cache;

use strict;
use warnings;

our $cache_path;
our $cache_is_stale;

sub import {
    my $this_module = shift;
    my %args = @_;


    my $file  = delete $args{file} if exists $args{file};

    my $class = delete $args{class};

    if (%args) {
        require Data::Dumper;
        die "Unknown params passed to " . __PACKAGE__ .
            Data::Dumper::Dumper(\@_);
    }

    if ($class and $file) {
        die __PACKAGE__ . " received both a class and file param: $class, $file!";
    }

    return unless ($ENV{COMP_LINE});

    my $module_path;
    if ($class) {
        ($module_path,$cache_path) = _module_and_cache_paths_for_package($class);
        $cache_path ||= $module_path . '.opts';
    }
    else {
        use FindBin;
        $module_path = $FindBin::RealBin . '/' . $FindBin::RealScript;
        $cache_path = $file || $module_path . '.opts';
    }

    #print STDERR ">> mod $module_path class $cache_path\n";

    if (-e $cache_path) {
        my $my_mtime = (stat($module_path))[9];

        # if the module has a directory with changes newer than the module,
        # use its mtime as the change time
        my $module_dir = $module_path;
        $module_dir =~ s/.pm$//;
        if (-e $module_dir) {
            if ((stat($module_dir))[9] > $my_mtime) {
                $my_mtime = (stat($module_dir))[9];
            }
        }
        
        my $cache_mtime = (stat($cache_path))[9];
        unless ($cache_mtime >= $my_mtime) {
            print STDERR "\nstale completion cache: refreshing $cache_path...\n";
            unlink $cache_path;
        }
    }

    if ($cache_path and -e $cache_path) {
        my $fh;
        open($fh,$cache_path);
        if ($fh) {
            my $src = join('',<$fh>);
            require Getopt::Complete;
            my $spec = eval $src;
            if ($spec) {
                Getopt::Complete->import(@$spec);
            }
        }
    }
}

sub _module_and_cache_paths_for_package {
    my $class = shift;
    my $path = $class;
    $path =~ s/::/\//g;
    $path = '/' . $path . '.pm';
    
    my (@mod_paths) = map { ($_ . $path) } @INC;
    my (@cache_paths) = map { ($_ . $path . '.opts' ) } @INC;
    
    my ($module_path, $cache_path);
    ($module_path) = grep { -e $_ } @mod_paths;
    ($cache_path) = grep { -e $_ } @cache_paths;

    return ($module_path, $cache_path);
}

sub generate {
    print STDERR "ending\n";
    eval {
        print STDERR "evaling $cache_path\n";
        unless (-e $cache_path) {
            print STDERR "found $cache_path\n";
            no warnings;
            my $a = $Getopt::Complete::ARGS;
            print STDERR "args are $a\n";
            use warnings;
            if ($a) {
                print STDERR ">> got args $a\n";
                if (my $o = $a->options) {
                    print STDERR ">> got opts $o\n";
                    my $c = $o->{completion_handlers};
                    my @modules;
                    if ($c) {
                        print STDERR ">> got completions $c\n";
                        my $has_callbacks = 0;
                        for my $key (keys %$c) {
                            my $completions = $c->{$key};
                            if (ref($completions) eq 'SCALAR') {
                                push @modules, $$completions;
                            }
                            elsif(ref($completions) eq 'CODE') {
                                warn "cannot use cached completions with anonymous callbacks!";
                                $has_callbacks = 1;
                            }
                        }
                        unless ($has_callbacks) {
                            my $fh;
                            open($fh,$cache_path);
                            if ($fh) {
                                warn "caching options for $cache_path...\n";
                                my $src = Data::Dumper::Dumper($c);
                                #$src =~ s/^\$VAR1/\$${class}::OPTS_SPEC/;
                                #print STDERR ">> $src\n";
                                $fh->print($src);
                                #require Data::Dumper;
                                #my $src = Data::Dumper::Dumper($c);
                            }
                        }
                        for my $module (@modules) {
                            print STDERR "trying mod $module\n";
                            local $ENV{GETOPT_COMPLETE_CACHE} = 1;
                            eval "use $module";
                            die $@ if $@;
                            no strict;
                            no warnings;
                            $spec = ${ $class . '::OPTS_SPEC' };
                            my ($other_module_path,$other_cache_path) = _module_and_cache_paths_for_package($module);
                            $other_cache_path ||= $other_module_path . '.opts';
                            my $fh;
                            open($fh,$other_cache_path);
                            if ($fh) {
                                warn "caching options for $module at $other_cache_path...\n";
                                my $src = Data::Dumper::Dumper($c);
                                $src =~ s/^\$VAR1/\$${class}::OPTS_SPEC/;
                                #print STDERR ">> $src\n";
                                $fh->print($src);
                                #require Data::Dumper;
                                #my $src = Data::Dumper::Dumper($c);
                            }
                        }
                    }
                }
            }
        }
    };
    print STDERR ">>>> $@\n" if $@;
}

1;
