package Getopt::Complete;

use strict;
use warnings;

use version;
our $VERSION = qv(0.04);

use Getopt::Long;

our %COMPLETION_HANDLERS;
our @OPT_SPEC;
our %OPT_SPEC;

our %OPTS;

our $NO_EXIT_ON_ERRORS;
our $OPTS_OK;
our @ERRORS;

our $LONE_DASH_SUPPORT = 1;

sub import {    
    my $class = shift;

    do {
        no strict 'refs';
        my $pkg = caller();
        my $v = \%{ $pkg . "::OPTS" };
        unless (keys %$v) {
            *{ $pkg . "::OPTS" } = \%OPTS;
        }
    };

    # Parse out the options and completions specification. 
    %COMPLETION_HANDLERS = (@_);
    my $bare_args = 0;
    my $parse_errors;
    for my $key (sort keys %COMPLETION_HANDLERS) {
        my ($name,$spec) = ($key =~ /^([\w|-]\w*|\<\>|)(\W.*|)/);
        if (not defined $name) {
            print STDERR __PACKAGE__ . " is unable to parse '$key' from spec!";
            $parse_errors++;
            next;
        }
        my $handler = delete $COMPLETION_HANDLERS{$key};
        if ($handler and not ref $handler) {
            my $code;
            eval {
                $code = \&{ $handler };
            };
            unless (ref($code)) {
                print STDERR __PACKAGE__ . " $key! references callback $handler which is not found!  Did you use its module first?!";
                $parse_errors++;
            }
            $handler = $code;
        }
        $COMPLETION_HANDLERS{$name} = $handler;
        if ($name eq '<>') {
            $bare_args = 1;
            next;
        }
        if ($name eq '-') {
            if ($spec and $spec ne '!') {
                print STDERR __PACKAGE__ . " $key errors: $name is implicitly boolean!";
                $parse_errors++;
            }
            $spec ||= '!';
        }
        $spec ||= '=s';
        push @OPT_SPEC, $name . $spec;
        $OPT_SPEC{$name} = $spec;
        if ($spec =~ /[\!\+]/ and defined $COMPLETION_HANDLERS{$key}) {
            print STDERR __PACKAGE__ . " error on option $key: ! and + expect an undef completion list, since they do not have values!";
            $parse_errors++;
            next;
        }
        if (ref($COMPLETION_HANDLERS{$key}) eq 'ARRAY' and @{ $COMPLETION_HANDLERS{$key} } == 0) {
            print STDERR __PACKAGE__ . " error on option $key: an empty arrayref will never be valid!";
            $parse_errors++;
        }
    }
    if ($parse_errors) {
        exit 1;
    }

    if ($ENV{COMP_LINE}) {
        # This command has been set to autocomplete via "completeF".
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
            if ($OPT_SPEC{$name} =~ /[\!\+]/) {
                push @other_options, $previous;
                $previous = undef;
            }
        }
        @ARGV = @other_options;
        local $SIG{__WARN__} = sub { push @Getopt::Complete::ERRORS, @_ };
        $Getopt::Complete::OPTS_OK = Getopt::Long::GetOptions(\%OPTS,@OPT_SPEC);
        @Getopt::Complete::ERRORS = invalid_options();
        $Getopt::Complete::OPTS_OK = 0 if $Getopt::Complete::ERRORS;
        #print STDERR Data::Dumper::Dumper([$command,$current,$previous,\@other_options]);
        my @matches = $class->resolve_possible_completions($command,$current,$previous,\@other_options);
        print join("\n",@matches),"\n";
        exit;
    }
    else {
        # Normal execution of the program.
        # Process the command-line options and store the results.  
        my @orig_argv = @ARGV;
        do {
            local $SIG{__WARN__} = sub { push @Getopt::Complete::ERRORS, @_ };
            $Getopt::Complete::OPTS_OK = Getopt::Long::GetOptions(\%OPTS,@OPT_SPEC);
        };
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
        if (@ERRORS) {
            for my $error (@ERRORS) {
                chomp $error;
                warn __PACKAGE__ . ' ERROR:' . $error . "\n";
            }
            exit 1;
        }
        # RESTORE ARGV!  In case the developer doesn't want to use our processed options...
        @ARGV = @orig_argv;
    }
}

sub print_matches_and_exit {
    my $class = shift;
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
            @possibilities = map { length($_) ? ('--' . $_) : ('-') } grep { $_ ne '<>' } @args;
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
            if ($last_char eq "\t") {
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
        # there is one match
        # the shell will complete it if it is not already complete, and put a space at the end
        if ($nospace[0]) {
            # We don't want a space, and there is no way to tell bash that, so we trick it.
            if ($matches[0] eq $current) {
                # it IS done completing the word: return nothing so it doesn't stride forward with a space
                # it will think it has a bad completion, effectively
                @matches = ();
            }
            else {
                # it IS done completing the word: return nothing so it doesn't stride forward with a space
                # it is NOT done completing the word
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
        
        my ($dashes,$name,$spec);
        if ($key eq '<>') {
            $name = '<>',
            $spec = '=s@';
        }
        else {
            ($dashes,$name,$spec) = ($key =~ /^(\-*?)([\w|-]\w*|\<\>|)(\W.*|)/);
            #($dashes,$name,$spec) = ($key =~ /^(\-*)(\w+)(.*)/);
            if (not defined $name) {
                print STDERR "key $key is unparsable in " . __PACKAGE__ . " spec inside of $0 !!!";
                next;
            }
        }

        my @values = (ref($OPTS{$name}) ? @{ $OPTS{$name} } : $OPTS{$name});
        my $all_valid_values;
        for my $value (@values) {
            next if not defined $value;
            next if not defined $completions;
            if (ref($completions) eq 'CODE') {
                # we pass in the value as the "completeme" word, so that the callback
                # can be as optimal as possible in determining if that value is acceptable.
                $completions = $completions->(undef,$value,$key,\%OPTS);
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
            unless (grep { $_ eq $value } map { /(.*)\t$/ ? $1 : $_ } @valid_values) {
                my $msg = (($key || 'arguments') . " has invalid value $value.  Select from: " . join(", ", @valid_values) . "\n");
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
    $value ||= '';
    my @f =  grep { $_ !~/^\s+$/ } `bash -c "compgen -f '$value'"`; 
    chomp @f;
    if (@f == 1 and -d $f[0]) {
        $f[0] .= "/\t"; 
    }
    if (-d $value) {
        push @f, [$value];
        push @{$f[-1]},'-' if $LONE_DASH_SUPPORT;
    }
    else {
        push @f, ['-'] if $LONE_DASH_SUPPORT;
    }
    return \@f;
}

sub directories {
    my ($command,$value,$key,$opts) = @_;
    $value ||= '';
    my @f =  grep { $_ !~/^\s+$/ } `bash -c "compgen -d '$value'"`; 
    chomp @f;
    if (@f == 1 and -d $f[0]) {
        $f[0] .= "/\t"; 
    }
    if (-d $value) {
        push @f, [$value];
    }
    return \@f;
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
        #[ map { chomp } grep { $_ !~/^\s+$/ } `bash -c "compgen -$option '$value'"` ], 
        my @f =  grep { $_ !~/^\s+$/ } `bash -c "compgen -$option '$value'"`;
        chomp @f;
        return \@f;
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

Getopt::Complete - custom programmable shell completion for Perl apps

=head1 SYNOPSIS

In the Perl program "myprogram":

  use Getopt::Complete (
      'frog'        => ['ribbit','urp','ugh'],
      'fraggle'     => sub { return ['rock','roll'] },
      'quiet!'      => undef,
      'name'        => undef,
      'age=n'       => undef,
      'output'      => \&Getopt::Complete::files, 
      'runthis'     => \&Getopt::Complete::commands, 
      '<>'          => \&Getopt::Complete::directories, 
  );
  print "the frog says " . $OPTS{frog} . "\n";

In ~/.bashrc or ~/.bash_profile, or directly in bash:

  complete -C myprogram myprogram

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

This module makes it easy to add custom command-line completion to
Perl applications, and makes using the shell arguments in the 
program hassle-free as well.

The completion features currently work with the bash shell, which is 
the default on most Linux and Mac systems.  Patches for other shells 
are welcome.  

For more information go to:
 
 http://github.com/sakoht/Getopt--Complete-for-Perl/

=head1 OPTIONS PROCESSING

Getopt::Complete processes the command-line options at compile time.

The results are avaialble in an %OPTS hash:

  use Getopt::Complete (
    'mydir'     => 'd',
    'myfile'    => 'f',
    '<>'        =  ['monkey', 'taco', 'banana']
  );

  for $opt (keys %OPTS) {
    $val = $OPTS{$opt};
    print "$opt has value $val\n";
  }

Errors in shell argumentes result in messages to STDERR via warn(), and cause the 
program to exit during "use".  Getopt::Complete verifies that the option values specified
match their own completion list, and will otherwise add additional errors
explaining the problem.

The %OPTS hash is an alias for %Getopt::Complete::OPTS.  The alias is not created 
in the caller's namespaces if a hash named %OPTS already exists with data.

It is possible to override any part of the default process, including doing custom 
parsing, doing processing at run-time, and and preventing exit when there are errors.
See OVERRIDING PROCESSING DEFAULTS below for details.

=head1 PROGRAMMABLE COMPLETION BACKGROUND

The bash shell supports smart completion of words when the <TAB> key is pressed.
By default, after the prgram name is specified, bash will presume the word the user 
is typing a is a file name, and will attempt to complete the word accordingly.  Where
completion is ambiguous, the shell will go as far as it can and beep.  Subsequent
completion attempts at that position result in a list being shown of possible completions.

Bash can be configured to run a specific program to handle the completion task.  
The "complete" built-in bash command instructs the shell as-to how to handle 
tab-completion for a given command.  

This module allows a program to be its own word-completer.  It detects that the 
COMP_LINE and COMP_POINT environment variables, are set, and responds by returning 
completion values suitable for the shell _instead_ of really running the application.

See the manual page for "bash", the heading "Programmable Completion" for full 
details on the general topic.

=head1 HOW TO CONFIGURE PROGRAMMABLE COMPLETION

=over 4

=item 1

Put a "use Getopt::Complete" statement into your app as shown in the synopsis.  
The key-value pairs describe the command-line options available,
and their completions.

This should be at the TOP of the app, before any real processing is done.

Subsequent code can use %OPTS instead of doing any futher options
parsing.  Existing apps can have their call to Getopt::Long converted
into "use Getopt::Complete".

=item 2

Put the following in your .bashrc or .bash_profile:

  complete -C myprogram myprogram

=item 3

New logins will automatically run the above and become aware that your
program has programmable completion.  For shells you already
have open, run this to alert bash to your that your program has
custom tab-completion.

  source ~/.bashrc 

=back

Type the name of your app ("myprogram" in the example), and experiment
with using the <TAB> key to get various completions to test it.  Every time
you hit <TAB>, bash sets certain environment variables, and then runs your
program.  The Getopt::Complete module detects these variables, responds to the
completion request, and then forces the program to exit before really running 
your regular application code. 

IMPORTANT: Do not do steps #2 and #3 w/o doing step #1, or your application
will actually run "normally" every time you press <TAB> with it on the command-line!  
The module will not be present to detect that this is not a "real" execution 
of the program, and you may find your program is running when it should not.


=head1 KEYS IN THE OPTIONS SPECIFICATION

Each key in the list decribes an option which can be completed.  Any 
key usable in a Getopt:::Long GetOptions specification works here, 
(except as noted in BUGS below):

=over 4

=item an option name

A normal word is interpreted as an option name. The '=s' specifier is
presumed if no specifier is present.

  'p1' => [...]

=item a complete option specifier

Any specification usable by L<Getopt::Long> is valid as the key.
For example:

  'p1=s' => [...]       # the same as just 'p1'
  'p2=s@' => [...]      # expect multiple values

=item the '<>' symbol for "bare arguments"

This special key specifies how to complete non-option (bare) arguments.
It presumes multiple values are possible (like '=s@'):

Have an explicit list:
 '<>' = ['value1','value2','value3']

Do normal file completion:
 '<>' = 'files'

Take arbitrary values with no expectations:
 '<>' = undef

If there is no '<>' key specified, bare arguments will be treated as an error.

=back

=head1 VALUES IN THE OPTIONS SPECIFICATION

Each value describes how the option in question should be completed.

=over 4

=item array reference 

An array reference expliciitly lists the valid values for the option.

  In the app:

    use Getopt::Complete (
        'color'    => ['red','green','blue'],
    );

  In the shell:

    $ myprogram --color <TAB>
    red green blue

    $ myprogram --color blue
    (runs with no errors)

The list of value is also used to validate the user's choice after options
are processed:

    myprogram --color purple
    ERROR: color has invalid value purple: select from red green blue

See below for details on how to permit values which aren't shown in completions.

=item undef 

An undefined value indicates that the option is not completable.  No completions
will be offered by the application, though any value provided by the user will be
considered valid.

Note that this is distinct from returning an empty arrayref from a callback, which 
implies that there ARE known completions but the user has failed to match any of them.

Also note: this is the only valid completion for boolean parameters, since there is no 
value to specify on the command-line.

  use Getopt::Complete (
    'first_name'        => undef,
    'is_perky!'         => undef,
  );

=item subroutine callback 

When the list of valid values must be determined dynamically, a subroutine reference or
name can be specified.  If a name is specified, it should be fully qualified.  (If
it is not, it will be presumed to refer to one of the bash builtin completions types.
See BUILTIN COMPLETION TYPES below.)

The subroutine will be called, and is expected to return an arrayref of possiible matches.  
The arrayref will be treated as though it were specified directly in the specification.

As with explicit values, an empty arrayref indicated that there are no valid matches 
for this option, given the other params on the command-line, and the text already typed.
An undef value indicates that any value is valid for this parameter.

Parameters to the callback are described below.

=back

=head1 WRITING SUBROUTINE CALLBACKS

A subroutine callback is useful when the list of options to match must be dynamically generated.

It is also useful when knowing what the user has already typed helps narrow the search for
valid completions, or when iterative completion needs to occur (see PARTIAL COMPLETIONS below). 

The callback is expected to return an arrayref of valid completions.  If it is empty, no
completions are considered valid.  If an undefined value is returned, no completions are 
specified, but ANY arbitrary value entered is considered valid as far as error checking is
concerned.

The callback registerd in the completion specification will receive the following parameters:

=over 4

=item command name

Contains the name of the command for which options are being parsed.  This is $0 in most
cases, though hierarchical commands may have a name "svn commit" or "foo bar baz" etc.

=item current word

This is the word the user is trying to complete.  It may be an empty string, if the user hits <Tab>
without typing anything first.

=item option name 

This is the name of the option for which we are resolving a value.  It is typically ignored unless
you use the same subroutine to service multiple options.

A value of '<>' indicates an unnamed argument (a.k.a "bare argument" or "non-option" argument).

=item other opts 

It is the hashref resulting from Getopt::Long processing of all of the OTHER arguments.
This is useful when one option limits the valid values for another option. 

In some cases, the options which should be available change depending on what other
options are present, or the values available change depending on other options or their
values.

=back

The environment variables COMP_LINE and COMP_POINT have the exact text
of the command-line and also the exact character position, if more detail is 
needed in raw form than the parameters provide.

The return value is a list of possible matches.  The callback is free to narrow its results
by examining the current word, but is not required to do so.  The module will always return
only the appropriate matches.

=head2 EXAMPLE 

This app takes 2 parameters, one of which is dependent on the other:  

  use Getopt::Complete (
    type => ['names','places','things'],
    instance => sub {
            my ($command, $value, $option, $other_opts) = @_;
            if ($other_opts{type} eq 'names') {
                return [qw/larry moe curly/],
            }
            elsif ($other_opts{type} eq 'places') {
                return [qw/here there everywhere/],
            }
            elsif ($other_opts{type} eq 'things') {
                return [ query_database_matching("${value}%") ]
            }
            elsif ($otper_opts{type} eq 'surprsing') {
                # no defined list: take anything typed
                return undef;
            }
            else {
                # invalid type: no matches
                return []
            }
        }
   );

   $ myprogram --type people --instance <TAB>
   larry moe curly

   $ myprogram --type places --instance <TAB>
   here there everywhere

   $ myprogram --type surprising --instance <TAB>
   (no completions appear)   


=head1 BUILTIN COMPLETIONS

Bash has a list of built-in value types which it knows how to complete.  Any of the 
default shell completions supported by bash's "compgen" are supported by this module.

The list of builtin types supported as-of this writing are:

    files
    directories
    commands
    users
    groups
    environment
    services
    aliases
    builtins

See "man bash", in the Programmable Complete secion, and the "compgen" builtin command for more details.

To indicate that an argument's valid values are one of the above, use the exact string
after Getopt::Complete:: as the completion callback.  For example:

  use Getopt::Complete (
    infile  => 'Getopt::Complete::files',       
    outdir  => 'Getopt::Complete::directories', 
    myuser  => 'Getopt::Complete::users',
  );

The full name is alissed as the single-character compgen parameter name for convenience.
Further, because Getopt::Complete is the default namespace during processing, it can
be ommitted from callback function names.

The following are all equivalent.  They effectively produce the same list as 'compgen -f':

   file1 => \&Getopt::Complete::files
   file1 => \&Getopt::Complete::f
   file1 => 'Getopt::Complete::files'
   file1 => 'Getopt::Complete::f'
   file1 => 'files'
   file1 => 'f'


=head1 UNLISTED VALID VALUES

If there are options which should not be part of completion lists, but still count
as valid if passed-into the app, they can be in a final sub-array at the end.  This
list doesn't affect the completion system at all, just prevents errors in the
ERRORS array described above.

    use Getopt::Complete (
        'color'    => ['red','green','blue', ['yellow','orange']],
    );

    myprogram --color <TAB>
    red green blue

    myprogram --color orange
    # no errors

    myprogram --color purple
    # error
    
=head1 PARTIAL COMPLETIONS

Sometimes, the entire list of completions is too big to reasonable resolve and
return.  The most obvious example is filename completion at the root of a 
large filesystem.  In these cases, the completion of is handled in pieces, allowing
the user to gradually "drill down" to the complete value directory by directory.  
It is even possible to hit <TAB> to get one completion, then hit it again and get
more completion, in the case of single-sub-directory directories.

The Getopt::Complete module supports iterative drill-down completions from any
parameter configured with a callback.  It is completely valid to complete 
"a" with "aa" "ab" and "ac", but then to complete "ab" with yet more text.

Unless the shell knows, however that your "aa", "ab", and "ac" completions are 
in fact only partial completions, an inconvenient space will be added 
after the word on the terminal line, as the shell happily moves on to helping
the user enter the next argument

Partial completions are indicated in Getopt::Complete by adding a "\t" 
tab character to the end of the returned string.  This means you can
return a mix of partial and full completions, and it will respect each 
correctly.  (The "\t" is actually stripped-off before going to the shell
and internal hackery is used to force the shell to not put a space 
where it isn't needed.  This is not part of the bash programmable completion
specification.)

=head1 THE LONE DASH

A lone dash is often used to represent using STDIN instead of a file for applications which otherwise take filenames.

This is supported by all options which complete with the "files" builtin, though it does not appear in completions.
To disable this, set $Getopt::Complete::LONE_DASH = 0.

=head1 OVERRIDING COMPILE-TIME OPTION PARSING 

Getopt::Complete makes a lot of assumptions in order to be easy to use in the
default case.  Here is how to override that behavior if it's not what you want.

To prevent Getopt::Complete from exiting at compile time if there are errors,
the NO_EXIT_ON_ERRORS flag should be set first, at compile time, before using
the Getopt::Complete module as follows:

 BEGIN { $Getopt:Complete::NO_EXIT_ON_ERRORS = 1; }

This should not affect completions in any way (it will still exit if it realizes
it is talking to bash, to prevent accidentally running your program).

Errors will be retained in:
 
 @Getopt::Complete::ERRORS

This module restores @ARGV to its original state after processing, so 
independent option processing can be done if necessary.  The full
spec imported by Getopt::Complete is stored as:

 @Getopt::Complete::OPT_SPEC;

With the flag above, set, you can completely ignore, or partially ignore,
the options processing which happens automatically.

You can also adjust how option processing happens inside of Getopt::Complete.
Getopt::Complete wraps Getopt::Long to do the underlying option parsing.  It uses
GetOptions(\%h, @specification) to produce the %OPTS hash.  Customization of
Getopt::Long should occur in a BEGIN block before using Getopt::Complete.  

 
=head1 DEVELOPMENT

  git clone git://github.com/sakoht/Getopt--Complete-for-Perl.git

=head1 BUGS

The logic to "shorten" the completion options shown in some cases is still in development. 
This means that filename completion shows full paths as options instead of just the basename of the file in question.

Some uses of Getopt::Long will not work currently: multi-name options, +, :, --no-*, --no*.

Currently this module only supports bash, though other shells could be added easily.

There is logic in development to have the tool possibly auto-update the user's .bashrc / .bash_profile, but this
is incomplete.

=head1 SEE ALSO

L<Getopt::Long> is the definitive options parser, wrapped by this module.

=head1 AUTHOR

Scott Smith (sakoht at cpan)

=cut

