package Getopt::Complete::Args;

use strict;
use warnings;

use version;
our $VERSION = qv('0.6');

use Getopt::Long;
use Scalar::Util;

sub new {
    my $class = shift;
    my $self = bless {
        'options' => undef,
        'values' => {},
        'errors' => [],
        'argv' => undef,
        @_,
    }, $class;

    unless ($self->{argv}) {
        die "No argv passed to " . __PACKAGE__ . " constructor!";
    }
   
    my $options = $self->{options};

    unless ($options) {
        die "No options passed to " . __PACKAGE__ . " constructor!";
    }

    my $type = ref($options);
    if (not $type) {
        die "Expected Getopt::Complete::Options, or a constructor ARRAY/HASH for ''options''.  Got: $type $options.";
    }
    elsif ($type eq 'ARRAY') {
        $self->{options} = Getopt::Complete::Options(@$options);
    }
    elsif ($type eq 'HASH') {
        $self->{options} = Getopt::Complete::Options(%$options);
    }
    elsif (Scalar::Util::blessed($options)) {
        if (not $options->isa("Getopt::Complete::Options")) {
            die "Expected Getopt::Complete::Options, or a constructor ARRAY/HASH for ''options''.  Got: $options.";
        }
    }
    else {
        die "Expected Getopt::Complete::Options, or a constructor ARRAY/HASH for ''options''.  Got reference $options.";
    }
    
    $self->_init();

    return $self;
}

for my $method (qw/sub_commands option_names option_specs option_spec completion_handler/) {
    no strict 'refs';
    *{$method} = sub {
        my $self = shift;
        my $options = $self->options;
        return $options->$method(@_);
    }
}

sub argv {
    @{ shift->{argv} };
}

sub options {
    shift->{options};
}

sub sub_command_path { shift->{'values'}{'>'} }

sub bare_args { shift->{'values'}{'>'} }

sub option_value {
    my $self = shift;
    my $name = shift;
    my $value = $self->{'values'}{$name};
    return $value;
}

sub errors {
    @{ shift->{errors} }
}

sub _init {
    my $self = shift; 
    
    # as long as the first word is a valid sub-command, drill down to the subordinate options list,
    # and also shift the args into a special buffer
    # (if you have sub-commands AND bare arguments, and the arg is a valid sub-command ...don't do that
    local @ARGV = @{ $self->{argv} };
    my @sub_command_path;
    while (@ARGV and my $delegate = $self->options->completion_handler('>' . $ARGV[0])) {
        push @sub_command_path, shift @ARGV;
        $self->{options} = $delegate;
    }

    my %values;
    my @errors;

    do {
        local $SIG{__WARN__} = sub { push @errors, @_ };
        my $retval = Getopt::Long::GetOptions(\%values,$self->options->option_specs);
        if (!$retval and @errors == 0) {
            push @errors, "unknown error processing arguments!";
        }
    };

    if (@ARGV) {
        if ($self->options->completion_handler('<>')) {
            my $a = $values{'<>'} ||= [];
            push @$a, @ARGV;
        }
        else {
            for my $arg (@ARGV) {
                push @errors, "unexpected unnamed arguments: $arg";
            }
        }
    }

    if (@sub_command_path) {
        $values{'>'} = \@sub_command_path;
    }

    %{ $self->{'values'} } = %values;
    
    if (my @more_errors = $self->_validate_values()) {
        push @errors, @more_errors;
    }

    @{ $self->{'errors'} } = @errors;

    return (@errors ? () : 1);
}


sub _validate_values {
    my $self = shift;

    my @failed;
    for my $key (keys %{ $self->options->{completion_handlers} }) {
        my $completions = $self->options->completion_handler($key);

        my ($dashes,$name,$spec);
        if ($key eq '<>') {
            $name = '<>',
            $spec = '=s@';
        }
        else {
            ($dashes,$name,$spec) = ($key =~ /^(\-*?)([\w|-]+|\<\>|)(\W.*|)/);
            #($dashes,$name,$spec) = ($key =~ /^(\-*)(\w+)(.*)/);
            if (not defined $name) {
                print STDERR "key $key is unparsable in " . __PACKAGE__ . " spec inside of $0 !!!";
                next;
            }
        }

        my $value_returned = $self->option_value($name);
        my @values = (ref($value_returned) ? @$value_returned : $value_returned);
        
        my $all_valid_values;
        for my $value (@values) {
            next if not defined $value;
            next if not defined $completions;
            if (ref($completions) eq 'CODE') {
                # we pass in the value as the "completeme" word, so that the callback
                # can be as optimal as possible in determining if that value is acceptable.
                $completions = $completions->(undef,$value,$key,$self);
                if (not defined $completions or not ref($completions) eq 'ARRAY' or @$completions == 0) {
                    # if not, we give it the chance to give us the full list of options
                    $completions = $self->completion_handler($key)->(undef,undef,$key,{});
                }
            }
            unless (ref($completions) eq 'ARRAY') {
                warn "unexpected completion specification for $key: $completions???";
                next;
            }
            my @valid_values = @$completions;
            if (ref($valid_values[-1]) eq 'ARRAY') {
                push @valid_values, @{ pop(@valid_values) };
            }
            unless (grep { $_ eq $value } map { /(.*)\t$/ ? $1 : $_ } @valid_values) {
                my $label = ($key eq '<>' ? "invalid argument $value." : "$key has invalid value $value."); 
                my $msg = ($label  . ".  Select from: " . join(", ", map { /^(.+)\t$/ ? $1 : $_ } @valid_values) . "\n");
                push @failed, $msg;
            }
        }
    }
    return @failed;
}

sub resolve_possible_completions {
    my ($self, $command, $current, $previous) = @_;

    my $all = $self->{values};

    $previous = '' if not defined $previous;

    my @possibilities;

    my ($dashes,$resolve_values_for_option_name) = ($previous =~ /^(--)(.*)/); 
    if (not length $previous) {
        # no specific option is before this: a sub-command, a bare argument, or an option name
        if ($current =~ /^(-+)/
            or (
                $current eq ''
                and not $self->sub_commands
                and not $self->option_spec('<>')
            )
        ) {
            # the incomplete word is an option name
            my @args = $self->option_names;
            
            # We only show the negative version of boolean options 
            # when the user already has "--no-" on the line.
            # Otherwise, we just include --no- as a possible (partial) completion
            no warnings; #########
            my %boolean = map { $_ => 1 } grep { $self->option_spec($_) =~ /\!/ } grep { $_ ne '<>' and substr($_,0,1) ne '>' }  @args;
            my $show_negative_booleans = ($current =~ /^--no-/ ? 1 : 0);
            @possibilities = 
                map { length($_) ? ('--' . $_) : ('-') } 
                map {
                    ($show_negative_booleans and $boolean{$_} and not substr($_,0,3) eq 'no-')
                        ? ($_, 'no-' . $_)
                        : $_
                }
                grep {
                    not (defined $self->option_value($_) and not $self->option_spec($_) =~ /@/)
                }
                grep { $_ ne '<>' and $_ ne '>' } 
                @args;
            if (%boolean and not $show_negative_booleans) {
                # a partial completion for negating booleans when we're NOT
                # already showing the complete list
                push @possibilities, "--no-\t";
            }
        }
        else {
            # bare argument or sub-command
            $resolve_values_for_option_name = '<>';
        }
    }

    if ($resolve_values_for_option_name) {
        # either a value for a named option, or a bare argument.
        if (my $handler = $self->completion_handler($resolve_values_for_option_name)) {
            # the incomplete word is a value for some option (possible the option '<>' for bare args)
            if (defined($handler) and not ref($handler) eq 'ARRAY') {
                $handler = $handler->($command,$current,$previous,$all);
            }
            unless (ref($handler) eq 'ARRAY') {
                die "values for $previous must be an arrayref! got $handler\n";
            }
            @possibilities = @$handler;
        }
        else {
            # no possibilities
            # print STDERR "recvd: " . join(',',@_) . "\n";
            @possibilities = ();
        }

        if ($resolve_values_for_option_name eq '<>') {
            push @possibilities, $self->sub_commands;
        }
    }

    my $uncompletable_valid_possibilities = pop @possibilities if ref($possibilities[-1]);

    # Determine which possibilities will actually match the current word
    # The shell does this for us, but we need to do it to predict a few things
    # and to adjust what we show the shell.
    # This loop also determines which options should complete with a space afterward,
    # and which options can be abbreviated when showing a list for the user.
    my @matches; 
    my @nospace;
    my @abbreviated_matches;
    for my $p (@possibilities) {
        my $i =index($p,$current);
        if ($i == 0) {
            my $m;
            if (substr($p,length($p)-1,1) eq "\t") {
                # a partial match: no space at the end so the user can "drill down"
                $m = substr($p,0,length($p)-1);
                $nospace[$#matches+1] = 1;
            }
            else {
                $m = $p;
                $nospace[$#matches+1] = 0;
            }
            if (substr($m,0,1) eq "\t") {
                # abbreviatable...
                # (nothing does this currently, and the code below which uses it does not work yet)
                my ($prefix,$abbreviation) = ($m =~ /^\t(.*)\t(.*)$/);
                push @matches, $prefix . $abbreviation;
                push @abbreviated_matches, $abbreviation;
            }
            else {
                push @matches, $m;
                push @abbreviated_matches, $m;
            }
        }
    }

    if (@matches == 1) {
        # there is one match
        # the shell will complete it if it is not already complete, and put a space at the end
        if ($nospace[0]) {
            # We don't want a space, and there is no way to tell bash that, so we trick it.
            if ($matches[0] eq $current) {
                # It IS done completing the word: return nothing so it doesn't stride forward with a space
                # It will think it has a bad completion, effectively.
                @matches = ();
            }
            else {
                # It is NOT done completing the word.
                # We return 2 items which start with the real value, but have an arbitrary ending.
                # It will show everything but that ending, and then stop.
                push @matches, $matches[0];
                $matches[0] .= 'A';
                $matches[1] .= 'B';
            }
        }
        else {
            # we do want a space, so just let this go normally
        }
    }
    else {
        # There are multiple matches to the text already typed.
        # If all of them have a prefix in common, the shell will complete that much.
        # If not, it will show a list.
        # We may not want to show the complete text of each word, but a shortened version,
        my $first_mismatch = eval {
            my $pos;
            no warnings;
            for ($pos=0; $pos < length($matches[0]); $pos++) {
                my $expected = substr($matches[0],$pos,1);
                for my $match (@matches[1..$#matches]) {  
                    if (substr($match,$pos,1) ne $expected) {
                        return $pos;            
                    }
                }
            }
            return $pos;
        };
        

        # NOTE: nothing does this currently, and the code below does not work.
        # Enable to get file/directory completions to be short, like is default in the shell. 
        if (0) {
            my $current_length = length($current);
            if (@matches and ($first_mismatch == $current_length)) {
                # No partial completion will occur: the shell will show a list now.
                # Attempt abbreviation of the displayed options:

                my @matches = @abbreviated_matches;

                #my $cut = $current;
                #$cut =~ s/[^\/]+$//;
                #my $cut_length = length($cut);
                #my @matches =
                #    map { substr($_,$cut_length) } 
                #    @matches;

                # If there are > 1 abbreviated items starting with the same character
                # the shell won't realize they're abbreviated, and will do completion
                # instead of listing options.  We force some variation into the list
                # to prevent this.
                my $first_c = substr($matches[0],0,1);
                my @distinct_firstchar = grep { substr($_,0,1) ne $first_c } @matches[1,$#matches];
                unless (@distinct_firstchar) {
                    # this puts an ugly space at the beginning of the completion set :(
                    push @matches,' '; 
                }
            }
            else {
                # some partial completion will occur, continue passing the list so it can do that
            }
        }
    }

    return @matches;
}

1;

=pod 

=head1 NAME

Getopt::Complete::Args - a set of option/value pairs 

=head1 VERSION

This document describes Getopt::Complete::Args v0.6.

=head1 SYNOPSIS

This is used internally by Getopt::Complete during compile.

A hand-built implementation might use the objects directly, and 
look like this:

 # process @ARGV...
 
 my $args = Getopt::Complete::Args->new(
    options => [                            # or pass a Getopt::Complete::Options directly                          
        'myfiles=s@' => 'f',
        'name'       => 'u',
        'age=n'      => undef,
        'fast!'      => undef,
        'color'      => ['red','blue','yellow'],
    ]
    argv => \@ARGV
 );

 $args->options->handle_shell_completion;   # support 'complete -C myprogram myprogram'

 if (my @e = $args->errors) {
    for my $e (@e) {
        warn $e;
    }
    exit 1; 
 }

 # on to normal running of the program...

 for my $name ($args->option_names) {
    my $spec = $args->option_spec($name);
    my $value = $args->option_value($name);
    print "option $name has specification $spec and value $value\n";
 }

=head1 DESCRIPTION

An object of this class describes a set of option/value pairs, built from a L<Getopt::Complete::Options> 
object and a list of command-line arguments (@ARGV).

This is the class of the $Getopt::Complete::ARGS object, and $ARGS alias created at compile time.
It is also the source of the %ARGS hash injected into both of those namepaces at compile time.

=head1 METHODS

=over 4

=item argv

Returns the list of original command-line arguments.

=item options

Returns the L<Getopt::Complete::Options> object which was used to parse the command-line.

=item option_value($name)

Returns the value for a given option name after parsing.

=item option_spec($name)

Returns the GetOptions specification for the parameter in question.

=item opion_handler($name)

Returns the arrayref or code ref which handles resolving valid completions.

=back

=head1 SEE ALSO

L<Getopt::Complete>, L<Getopt::Complete::Options>, L<Getopt::Complete::Compgen>

=head1 COPYRIGHT

Copyright 2009 Scott Smith and Washington University School of Medicine

=head1 AUTHORS

Scott Smith (sakoht at cpan .org)

=head1 LICENSE

This program is free software; you can redistribute it and/or modify it under
the same terms as Perl itself.

The full text of the license can be found in the LICENSE file included with this
module.

=cut

