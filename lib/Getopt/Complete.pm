
use strict;
use warnings;

package Getopt::Complete;

use version;
our $VERSION = qv(0.02);

our %handlers;

sub import {    
    my $class = shift;
    %handlers = (@_);

    for my $key (sort keys %handlers) {
        unless ($key eq '' or $key =~ /^--/) {
            my $new_key = '--' . $key;
            $handlers{$new_key} = delete $handlers{$key};
            $key = $new_key;
        }
    }

    if ($ENV{COMP_LINE}) {
        # This command has been set to autocomplete via "complete -F".
        # More info about the command linie iis available than with -C.
        # SUPPORT IS INCOMPLETE FOR THIS WAY OF AUTO-COMPLETING!

        my $left = substr($ENV{COMP_LINE},0,$ENV{COMP_POINT});
        my $current = '';
        if ($left =~ /([^\=\s]+)$/) {
            $current = $1;
            $left = substr($left,0,length($left)-length($current));
        }
        $left =~ s/\s+$//;

        my @other_options = split(/\s+/,$left);
        my $command = $other_options[0];
        my $previous = pop @other_options if $other_options[-1] =~ /^-/;
        Getopt::Complete::print_matches_and_exit($command,$current,$previous,\@other_options);
    }
    elsif (my $shell = $ENV{GETOPT_COMPLETE}) {
        # This command has been set to autocomplete via "complete -C".
        # This is easiest to set-up, but less info about the command-line is present.
        if ($shell eq 'bash') {
            my ($command, $current, $previous) = (map { defined $_ ? $_ : '' } @ARGV);
            $previous = '' unless $previous =~ /^-/; 
            Getopt::Complete::print_matches_and_exit($command,$current,$previous);
        }
        else {
            print STDERR "\ncommand-line completion: unsupported shell $shell\n";
            print " \n";
            exit;
        }
    }
    else {
        # Normal execution of the program (or else an error in use of "complete" to tell bash about this program.)
    }
}


sub print_matches_and_exit {
    my ($command, $current, $previous, $all) = @_;
    no warnings;
    #print STDERR "recvd: " . join(',',@_) . "\n";
    #print "11 22 33\n";
    #exit;
 
    my @args = map { /^-+(.*)/ ? ($1) : () } keys %handlers;
    
    my @possibilities;
    if ($current =~ /^(-+)/ and not length($previous)) {
        # a new option argment (starts with '-')
        @possibilities = map { '--' . $_ } @args;
    }
    elsif (my $handler = $handlers{$previous}) {
        # a value for the key just before it
        # or a bare, non-option argument
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
        @possibilities = ();
    }

    my @matches; 
    for my $p (@possibilities) {
        my $i =index($p,$current);
        if ($i == 0) {
            push @matches, $p; 
        }
    }

    print join("\n",@matches),"\n";
    exit;
}

# Manufacture the long and short sub-names on the fly.

for my $subname (qw/
    files
    directories
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
        [ grep { $_ !~/^\s+$/ } `bash -c 'compgen -$option'` ], 
    };
    no strict 'refs';
    *$subname = $code;
    *$option = $code;
}

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
# It's easier to do for the user than explain.

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
      ''          => \&Getopt::Complete::environment, 
  ;

In ~/.bashrc or ~/.bash_profile, or directly in bash:

  complete -C 'GETOPT_COMPLETE=bash myprogram1' myprogram1
  complete -C 'GETOPT_COMPLETE=bash myprogram2' myprogram2
  ...


When the user types:
  myprogram --f<TAB>

The shell will add an "r", and will then present the options:
  frog fraggle

When they type "o"<TAB>, it will complete the word --frog, and
offer the following options:
  ribbit urp ugh

When they type "r"<TAB>, it will complete the word "ribbit".

=head1 DESCRIPTION

Perl applications using the Getopt::Complete module can "self serve"
as their own shell-completion utility.

When "use Getopt::Complete" is encountered at compile time, the application
will detect that it is being run by bash to do shell completion, and
will respond to bash instead of running the app.

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

=back

The return value is a list of possible matches.  The callback is free to narrow its results
by examining the current word, but is not required to do so.  The module will always return
only the appropriate matches.

=head1 USING BUILTIN COMPLETIONS

Any of the default shell completions supported by bash's compgen are supported by this module.
The full name is alissed as the single-character compgen parameter name for convenience.

See "man bash", in the Programmable Complete secion for more details.

=head1 SEEING THE WHOLE COMMAND LINE IN CALLBACKS

Sometimes, the completions for one option will vary depending on what else is on the 
command-line.  If the "complete" command is given a shell function, that function
will have access to more information about the commmand line, and will pass those
values through to the Perl application.

This function should be present in the .bashrc or .bash_profile:

  _getopt_complete() {
      export COMP_LINE COMP_POINT;
      COMPREPLY=( $( ${COMP_WORDS[0]} ) )
  }

The "complete" command to use to get extra features on the Perl side is:

  complete -F _getopt_complete myprogram1
  complete -F _getopt_complete myprogram2
  ...

This has the same effect as the simple "complete -C" entry point, except that
the remaining @ARGV is passed as an arrayref to any subroutine callbacks.

  sub {
    my ($incomplete_word, $field_name_to_the_left_if_applicable, $remaining_argv_oh_goody) = @_;
    ...
    return \@completions; 
  }

=head1 BUGS

Currently only supports bash, though other shells could be added easily.

Imperfect handling of cases where the value in a key-value starts with a dash.

There is logic in development to have the tool possibly auto-update the user's .bashrc / .bash_profile, but this
is still in development.

=head1 AUTHOR

Scott Smith <sakoht aht seepan>

=cut

