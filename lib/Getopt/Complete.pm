package Getopt::Complete;

use strict;
use warnings;

use version;
our $VERSION = qv(0.03);

use Getopt::Long;

our %COMPLETION_HANDLERS;
our @OPT_SPEC;
our %OPT_SPEC;

our %OPTS;
our $OPTS_OK;
our @ERRORS;

sub import {    
    my $class = shift;
    
    # Parse out the options and completions specification. 
    %COMPLETION_HANDLERS = (@_);
    my $bare_args = 0;
    for my $key (sort keys %COMPLETION_HANDLERS) {
        my ($name,$spec) = ($key =~ /^([\w|\-]\w+|\<\>)(.*)/);
        if (not defined $name) {
            print STDERR __PACKAGE__ . " is unable to parse $key! from spec!";
            next;
        }
        $COMPLETION_HANDLERS{$name} = delete $COMPLETION_HANDLERS{$key};
        if ($name eq '<>') {
            $bare_args = 1;
            next;
        }
        $spec ||= '=s';
        push @OPT_SPEC, $name . $spec;
        $OPT_SPEC{$name} = $spec;
    }

    if ($ENV{COMP_LINE}) {
        # This command has been set to autocomplete via "complete -F".
        # This is more complicated than the -C option to configure, but more powerful.
        my $left = substr($ENV{COMP_LINE},0,$ENV{COMP_POINT});
        my $current = '';
        if ($left =~ /([^\=\s]+)$/) {
            $current = $1;
            $left = substr($left,0,length($left)-length($current));
        }
        $left =~ s/\s+$//;

        my @other_options = split(/\s+/,$left);
        my $command = $other_options[0];
        my $previous = pop @other_options if $other_options[-1] =~ /^--/;
        # it's hard to spot the case in which the previous word is "boolean", and has no value specified
        if ($previous) {
            my ($name) = ($previous =~ /^-+(.*)/);
            if ($OPT_SPEC{$name} =~ /\!/) {
                push @other_options, $previous;
                $previous = undef;
            }
        }
        @ARGV = @other_options;
        $Getopt::Complete::OPTS_OK = Getopt::Long::GetOptions(\%OPTS,@OPT_SPEC);
        @Getopt::Complete::ERRORS = invalid_options();
        $Getopt::Complete::OPTS_OK = 0 if $Getopt::Complete::ERRORS;
        #print STDERR Data::Dumper::Dumper([$command,$current,$previous,\@other_options]);
        Getopt::Complete->print_matches_and_exit($command,$current,$previous,\@other_options);
    }
    elsif (my $shell = $ENV{GETOPT_COMPLETE}) {
        # This command has been set to autocomplete via "complete -C".
        # This is easiest to set-up, but less info about the command-line is present.
        if ($shell eq 'bash') {
            my ($command, $current, $previous) = (map { defined $_ ? $_ : '' } @ARGV);
            $previous = '' unless $previous =~ /^-/; 
            Getopt::Complete->print_matches_and_exit($command,$current,$previous);
        }
        else {
            print STDERR "\ncommand-line completion: unsupported shell $shell.  Please submit a patch!  (Or fix your topo.)\n";
            print " \n";
            exit;
        }
    }
    else {
        # Normal execution of the program.
        # Process the command-line options and store the results.  
        my @orig_argv = @ARGV;
        local $SIG{__WARN__} = sub { push @Getopt::Complete::ERRORS, @_ };
        $Getopt::Complete::OPTS_OK = Getopt::Long::GetOptions(\%OPTS,@OPT_SPEC);
        if (@ARGV) {
            if ($bare_args) {
                my $a = $Getopt::Complete::OPTS{'<>'} ||= [];
                push @$a, @ARGV;
            }
            else {
                $Getopt::Complete::OPTS_OK = 0;
                for my $arg (@ARGV) {
                    push @Getopt::Complete::ERRORS, "unexpected unnamed arguments: $arg";
                }
            }
        }
        if (my @more_errors = invalid_options()) {
            $Getopt::Complete::OPTS_OK = 0;
            push @Getopt::Complete::ERRORS, @more_errors;
        }
        # RESTORE ARGV!  In case the developer doesn't want to use our processed options...
        @ARGV = @orig_argv;
    }
}

sub print_matches_and_exit {
    my $class = shift;
    my @matches = $class->resolve_possible_completions(@_);
    print join("\n",@matches),"\n";
    exit;
}


sub resolve_possible_completions {
    my ($self,$command, $current, $previous, $all) = @_;

    $previous = '' if not defined $previous;

    my @args = keys %COMPLETION_HANDLERS;
    my @possibilities;

    my ($dashes,$resolve_values_for_option_name) = ($previous =~ /^(--)(.*)/); 
    
    if (not length $previous) {
        # an unqalified argument, or an option name
        if ($current =~ /^(-+)/) {
            # the incomplete word is an option name
            @possibilities = map { '--' . $_ } grep { $_ ne '<>' } @args;
        }
        else {
            # bare argument
            $resolve_values_for_option_name = '<>';
        }
    }

    if ($resolve_values_for_option_name) {
        # either a value for a named option, or a bare argument.
        if (my $handler = $COMPLETION_HANDLERS{$resolve_values_for_option_name}) {
            # the incomplete word is a value for some option (possible the option '<>' for bare args)
            if (defined($handler) and not ref($handler) eq 'ARRAY') {
                $handler = $handler->($command,$current,$previous,\%Getopt::Complete::OPTS);
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
    }

    my @matches; 
    my @nospace;
    for my $p (@possibilities) {
        my $i =index($p,$current);
        if ($i == 0) {
            my $last_char = substr($p,length($p)-1,1);
            if ($last_char eq "\b") {
                #print STDERR ">> nospace on $p\n";
                ##print STDERR Data::Dumper->new([$p])->Useqq(1)->Dump;
                push @matches, substr($p,0,length($p)-1);
                $nospace[$#matches] = 1;
            }
            else {
                #print STDERR ">> space on $p\n";
                push @matches, $p;
                $nospace[$#matches] = 0;
            }
        }
    }

    if (@matches == 1) {
        #print STDERR ">> one match\n";
        # there is one match
        # the shell will complete it if it is not already complete, and put a space at the end
        if ($nospace[0]) {
            #print STDERR ">> no space\n";
            # We don't want a space, and there is no way to tell bash that, so we trick it.
            if ($matches[0] eq $current) {
                #print STDERR ">> already complete\n";
                # it IS done completing the word: return nothing so it doesn't stride forward with a space
                # it will think it has a bad completion, effectively
                @matches = ();
            }
            else {
                #print STDERR ">> incomplete\n";
                # it IS done completing the word: return nothing so it doesn't stride forward with a space
                # it is NOT done completing the word
                # We return 2 items which start with the real value, but have an arbitrary ending.
                # It will show everything but that ending, and then stop.
                #print STDERR ">>> matches were @matches\n";
                push @matches, $matches[0];
                $matches[0] .= 'A';
                $matches[1] .= 'B';
                #print STDERR ">>> matches are now @matches\n";
            }
        }
        else {
            # we do want a space, so just let this go normally
            #print STDERR ">> we want space\n";
        }
    }
    else {
        ##print STDERR ">> multiple matches...\n";
        # There are multiple matches.
        # If all of them have a prefix in common, it will complete that much.
        # If not, it will show a list.
        # We may not want to show the complete text of each word, but a shortened version.
        my $first_mismatch = eval {
            my $pos;
            no warnings;
            for ($pos=0; $pos < length($matches[0]); $pos++) {
                my $expected = substr($matches[0],$pos,1);
                for my $match (@matches[1..$#matches]) {  
                    if (substr($match,$pos,0) ne $expected) {
                        return $pos;            
                    }
                }
            }
            return $pos;
        };
        if ($first_mismatch == 0) {
            # no partial completion will occur, the shell will show a list now
            # TODO: HERE IS WHERE WE ABBREVIATE THE MATCHES FOR DISPLAY
        }
        else {
            # some partial completion will occur, continue passing the list so it can do that
        }
    }

    return @matches;
}


sub invalid_options {
    my @failed;
    for my $key (sort keys %COMPLETION_HANDLERS) {
        my $completions = $COMPLETION_HANDLERS{$key};
        
        next if ($key eq '<>');
        my ($dashes,$name,$spec) = ($key =~ /^(\-*)(\w+)(.*)/);
        if (not defined $name) {
            print STDERR "key $key is unparsable in " . __PACKAGE__ . " spec inside of $0 !!!";
            next;
        }

        my @values = (ref($OPTS{$name}) ? @{ $OPTS{$name} } : $OPTS{$name});
        my $all_valid_values;
        for my $value (@values) {
            next if not defined $value;
            next if not defined $completions;
            if (ref($completions) eq 'CODE') {
                # we pass in the value as the "completeme" word, so that the callback
                # can be as optimal as possible in determining if that value is acceptable.
                $completions = $completions->(undef,$value,$key);
                if (not defined $completions or not ref($completions) eq 'ARRAY' or @$completions == 0) {
                    # if not, we give it the chance to give us the full list of options
                    $completions = $COMPLETION_HANDLERS{$key}->(undef,undef,$key);
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
            unless (grep { $_ eq $value } @valid_values) {
                my $msg = (($key || 'arguments') . " has invalid value $value: select from @valid_values");
                push @failed, $msg;
            }
        }
    }
    return @failed;
}

# Support the shell-builtiin completions.
# Under development.  Replicating what the shell does w/ files and directories completely
# seems impossible.  You must use -o default on the complete command to get zero-match options to complete.

sub files {
    my ($command,$value,$key,$opts) = @_;
    my @f =  grep { $_ !~/^\s+$/ } `bash -c "compgen -f '$value'"`; 
    chomp @f;
    if (@f == 1 and -d $f[0]) {
        $f[0] .= "/\b";
    }
    return \@f;
}


sub directories {
    my ($command,$value,$key,$opts) = @_;
    my @f =  grep { $_ !~/^\s+$/ } `bash -c "compgen -d '$value'"`;
    chomp @f;
    if (@f == 1 and -d $f[0]) {
        $f[0] .= "/\b";
    }
    return \@f,[-d $value ? $value : ()];
}

no warnings;
*f = \&files;
*d = \&directories;
use warnings;

# Manufacture the long and short sub-names on the fly.
for my $subname (qw/
    commands
    users
    groups
    environment
    services
    aliases
    builtins
/) {
    my $option = substr($subname,0,1);
    my $code = sub {
        my ($command,$value,$key,$opts) = @_;
        [ map { chomp } grep { $_ !~/^\s+$/ } `bash -c "compgen -$option '$value'"` ], 
    };
    no strict 'refs';
    *$subname = $code;
    *$option = $code;
}

# Under development...
sub update_bashrc {
    use File::Basename;
    use IO::File;
    my $me = basename($0);

    my $found = 0;
    my $added = 0;
    if ($ENV{GETOPT_COMPLETE_APPS}) {
        my @apps = split('\s+',$ENV{GETOPT_COMPLETE_APPS});
        for my $app (@apps) {
            if ($app eq $me) {
                # already in the list
                return;
            }
        }
    }

    # we're not on the list: try to update .bashrc
    my $bashrc = "$ENV{HOME}/.bashrc";
    if (-e $bashrc) {
        my $bashrc_fh = IO::File->new($bashrc);
        unless ($bashrc_fh) {
            die "Failed to open $bashrc to add tab-completion for $me!\n";
        } 
        my @lines = $bashrc_fh->getlines();
        $bashrc_fh->close;
        
        for my $line (@lines) {
            if ($line =~ /^\s*export GETOPT_COMPLETE_APPS=/) {
                if (index($line,$me) == -1) {
                    $line =~ s/\"\s*$//;
                    $line .= ' ' . $me . '"' .  "\n";
                    $added++;
                }
                else {
                    $found++;
                }
            }
        }

        if ($added) {
            # append to the existing apps variable
            $bashrc_fh = IO::File->new(">$bashrc");
            unless ($bashrc_fh) {
                die "Failed to open $bashrc to add tab-completion for $me!\n";
            }
            $bashrc_fh->print(@lines);
            $bashrc_fh->close;
            return 1;
        }

        if ($found) {
            print STDERR "WARNING: Run this now to activate tab-completion: source ~/.bashrc\n";
            print STDERR "WARNING: This will occur automatically for subsequent logins.\n";
            return;
        }
    }

    # append a block of logic to the bashrc
    my $bash_src = <<EOS;
    # Added by the Getopt::Complete Perl module
    export GETOPT_COMPLETE_APPS="\$GETOPT_COMPLETE_APPS $me"
    for app in \$GETOPT_COMPLETE_APPS; do
        complete -C GETOPT_COMPLETE=bash\\ \$app \$app
    done
EOS
    my $bashrc_fh = IO::File->new(">>$bashrc");
    unless ($bashrc_fh) {
        die "Failed to open .bashrc: $!\n";
    }
    while ($bash_src =~ s/^ {4}//m) {}
    $bashrc_fh->print($bash_src);
    $bashrc_fh->close;

    return 1;
}

# At exit, ensure that command-completion is configured in bashrc for bash users.
# It's easier to do for the user than to explain.

END {
    # DISABLED!
    if (0 and $ENV{SHELL} =~ /\wbash$/) {
        if (eval { update_bashrc() }) {
            print STDERR "WARNING: Added command-line tab-completion to $ENV{HOME}/.bashrc.\n";
            print STDERR "WARNING: Run this now to activate tab-completion: source ~/.bashrc\n";
            print STDERR "WARNING: This will occur automatically for subsequent logins.\n";
        }
        if ($@) {
            warn "WARNING: failed to extend .bashrc to handle tab-completion! $@";
        }
    }
}

1;

=pod 

=head1 NAME

Getopt::Complete - add custom dynamic bash autocompletion to Perl applications

=head1 SYNOPSIS

In the Perl program "myprogram":

  use Getopt::Complete
      '--frog'    => ['ribbit','urp','ugh'],
      '--fraggle' => sub { return ['rock','roll'] },
      '--person'  => \&Getopt::Complete::users, 
      '--output'  => \&Getopt::Complete::files, 
      '--exec'    => \&Getopt::Complete::commands, 
      '<>'        => \&Getopt::Complete::environment, 
  ;

In ~/.bashrc or ~/.bash_profile, or directly in bash:

  complete -C 'GETOPT_COMPLETE=bash myprogram1' myprogram
  
Thereafter in the terminal (after next login, or sourcing the updated .bashrc):

  $ myprogram --f<TAB>
  $ myprogram --fr

  $ myprogram --fr<TAB><TAB>
  frog fraggle

  $ myprogram --fro<TAB>
  $ myprogram --frog 

  $ myprogram --frog <TAB>
  ribbit urp ugh

  $ myprogram --frog r<TAB>
  $ myprogram --frog ribbit

=head1 DESCRIPTION

Perl applications using the Getopt::Complete module can "self serve"
as their own shell-completion utility.

When "use Getopt::Complete" is encountered at compile time, the application
will detect that it is being run by bash (or bash-compatible shell) to do 
shell completion, and will respond to bash instead of running the app.

When running the program in "completion mode", bash will comminicate
the state of the command-line using environment variables and command-line
parameters.  The app will exit after sending a response to bash.  As
such the application should "use Getopt::Complete" before doing other
processing, and before parsing/modifying the enviroment or @ARGV. 

=head1 BACKGROUND ON BASH COMPLETION

The bash shell supports smart completion of words when the TAB key is pressed.

By default, bash will presume the word the user is typing is a file name, 
and will attempt to complete the word accordingly.  Bash can, however, be
told to run a specific program to handle the completion task.  The "complete" 
command instructs the shell as-to how to handle tab-completion for a given 
command.  

This module allows a program to be its own word-completer.  It detects
that the GETOPT_COMPLETE environment variable is set to the name of
some shell (currenly only bash is supported), and responds by
returning completion values suitable for that shell _instead_ of really 
running the application.

The "use"  statement for the module takes a list of key-value pairs 
to control the process.  The format is described below.

=head1 KEYS

Each key in the list decribes an option which can be completed.

=over 4

=item plain text

A normal word is interpreted as an option name.  Dashes are optional.
Getopt-style suffixes are ignored as well.

=item a blank string ('')

A blank key specifiies how to complete non-option (bare) arguments.

=back

=head1 VALUES

Each value describes how that option should be completed.

=over 4

=item array reference 

An array reference expliciitly lists the valid values for the option.

=item undef 

An undefined value indicates that the  option has no following value (for boolean flags)

=item subroutine reference 

This will be called, and expected to return an array of possiible matches.

=item plain text

A text string will be presumed to be a subroutine name, which will be called as above.

=back

There is a built-in subroutine which provides access to compgen, the bash built-in
which does completion on file names, command names, users, groups, services, and more.

See USING BUILTIN COMPLETIONS below.

=head1 USING SUBROUTINE CALLBACKS

A subroutine callback will always receieve two arguments:

=over 4

=item current word

This is the word the user is trying to complete.  It may be an empty string, if the user hits <Tab>
without typiing anything first.

=item previous option

This is the option argument to the left of the word the user is typing.  If the word to the left 
is not an option argument, or there is no word to the left besidies the command itself, this 
will be an empty string.

=item opts

It is the hashref resulting from Getopt::Long processing of all of the OTHER arguments.

This is useful when one option limits the valid values for another. 

This hashref is only available if bash requests completion via the -F option.
See COMPLETIONS WHICH REQUIRE EXAMINING THE ENTIRE COMMAND LINE below.

=back

The return value is a list of possible matches.  The callback is free to narrow its results
by examining the current word, but is not required to do so.  The module will always return
only the appropriate matches.

=head1 USING BUILTIN COMPLETIONS

Any of the default shell completions supported by bash's compgen are supported by this module.
The full name is alissed as the single-character compgen parameter name for convenience.

The list of builtins supported are:

    files
    directories
    commands
    users
    groups
    environment
    services
    aliases
    builtins

See "man bash", in the Programmable Complete secion for more details.

=head1 COMPLETIONS WHICH REQUIRE EXAMINING THE ENTIRE COMMAND LINE 

In some cases, the options which should be available change depending on what other
options are present, or the values available change depending on other options or their
values.

The standard "complete -C" does not supply the entire command-line to the completion
program, unfortunately.  Getopt::Complete, as of version v0.02, now recognizes when
bash is configured to call it with "complete -F".  Using this involves adding a
few more lines of code to your .bashrc or .bash_profile:

  _getopt_complete() {
      export COMP_LINE COMP_POINT;
      COMPREPLY=( $( ${COMP_WORDS[0]} ) )
  }

The "complete" command then can look like this in the .bashrc/.bash_profile: 

  complete -F _getopt_complete myprogram

This has the same effect as the simple "complete -C" entry point, except that
all callbacks which are subroutines will received two additional parameters:
1. the remaining parameters as an arrayref
2. the above already processed through GetOpt::Long into a hashref.

  use Getopt::Complete
    type => ['names','places'],
    instance => sub {
            my ($value, $key, $argv, $opts) = @_;
            if ($opts{type} eq 'names') {
                return [qw/larry moe curly/],
            }
            elsif ($opts{type} eq 'places') {
                return [qw/here there everywhere/],
            }
        }

=head1 BUGS

Currently only supports bash, though other shells could be added easily.

Imperfect handling of cases where the value in a key-value starts with a dash.

There is logic in development to have the tool possibly auto-update the user's .bashrc / .bash_profile, but this
is still in development.

=head1 AUTHOR

Scott Smith <sakoht aht seepan>

=cut

