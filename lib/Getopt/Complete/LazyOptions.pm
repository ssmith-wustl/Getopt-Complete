
package Getopt::Complete::LazyOptions;

our $AUTOLOAD;

sub new {
    my ($class, $callback) = @_;
    return bless { callback => $callback }, $class;
}

sub AUTOLOAD {
    my ($c,$m) = ($AUTOLOAD =~ /^(.*)::([^\:]+)$/);
    return if $m eq 'DESTROY';

    my $self = shift;
    my $callback = $self->{callback};
    my @spec;
    if (ref($callback) eq 'SCALAR') {
        no strict;
        no warnings;
        my $class = $$callback;
        my $path  = $class;
        $path =~ s/::/\//g;
        $path .= '.pm.opts';
        my @possible = map { $_ . '/' . $path } @INC;
        my @actual = grep { -e $_ } @possible;
        #print STDERR ">> possible @possible\n\nactual @actual\n\n";
        my $spec;
        if (@actual) {
            my $data = `cat $actual[0]`;
            $spec = eval $data;
        }
        else {
            print STDERR ">> redo $class!\n";
            local $ENV{GETOPT_COMPLETE_CACHE} = 1;
            eval "use $class";
            die $@ if $@;
            no strict;
            no warnings;
            $spec = ${ $class . '::OPTS_SPEC' };
            #print STDERR ">> got @spec\n";
        }
        @spec = @$spec;
    }
    else {
        @spec = $self->{callback}();
    }
    %$self = (
        sub_commands => [], 
        option_specs => {}, 
        completion_handlers => {}, 
        parse_errors => undef,
        %$self,
    );
    bless $self, 'Getopt::Complete::Options';
    $self->_init(@spec);
    $self->$m(@_);
}

1;

