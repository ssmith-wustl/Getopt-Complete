package Getopt::Complete;

use strict;
use warnings;

use version;
our $VERSION = qv('0.5');

use Getopt::Complete::Options;
use Getopt::Complete::Args;
use Getopt::Complete::Compgen;

our $ARGS;
our %ARGS;

our $LONE_DASH_SUPPORT = 1;

sub import {    
    my $class = shift;
    return unless @_;

    # The safe way to use this module is to specify args at compile time.  
    # This allows 'perl -c' to handle shell-completion requests.
    # Direct creation of objects is mostly for testing, and wrapper modules.
    
    # Make a single default Getopt::Complete::Options object,
    
    my $options = Getopt::Complete::Options->new(@_);
    
    # See if we are really just being run to respond to a shell completion request.
    # (in this case, the app will exit inside this call)

    $options->handle_shell_completion();

    # and then a single default Getopt::Complete::Args object.
    
    $ARGS = Getopt::Complete::Args->new(
        options => $options,
        argv => [@ARGV]
    );
    
    if (my @errors = $ARGS->errors) {
        for my $error ($ARGS->errors) {
            chomp $error;
            warn __PACKAGE__ . ' ERROR:' . $error . "\n";
        }
        exit 1;
    }

    # Then make it and its underlying hash available globally.
    
    *ARGS = \%{ $ARGS->{values} };
    
    # And export it into the caller's namespace

    do {
        no strict 'refs';
        my $pkg = caller();
        my $v;
        $v = ${ $pkg . "::ARGS" };
        unless (defined $v) {
            *{ $pkg . "::ARGS" } = \$ARGS;
        }
        $v = \%{ $pkg . "::ARGS" };
        unless (keys %$v) {
            *{ $pkg . "::ARGS" } = \%ARGS;
        }
    };
}

1;

=pod 

=head1 NAME

Getopt::Complete - custom programmable shell completion for Perl apps

=head1 VERSION

This document describes Getopt::Complete v0.5.

=head1 SYNOPSIS

In the Perl program "myprogram":

  use Getopt::Complete (
      'frog'        => ['ribbit','urp','ugh'],
      'fraggle'     => sub { return ['rock','roll'] },
      'quiet!'      => undef,
      'name'        => undef,
      'age=n'       => undef,
      'outfile=s@'  => 'files', 
      'outdir'      => 'directories'
      'runthis'     => 'commands',
      'username'    => 'users',
      '<>'          => 'directories', 
  );

  print "the frog says " . $ARGS{frog} . "\n";

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


=head1 OPTIONS PROCESSING

Getopt::Complete processes the command-line options at compile time.

The results are avaialble in an %ARGS hash, which is intended as a companion
to the @ARGV array generated natively by Perl.

  use Getopt::Complete (
    'mydir'     => 'd',
    'myfile'    => 'f',
    '<>'        =  ['monkey', 'taco', 'banana']
  );

  for $opt (keys %ARGS) {
    $val = $ARGS{$opt};
    print "$opt has value $val\n";
  }

Errors in shell argumentes result in messages to STDERR via warn(), and cause the 
program to exit during "use" call.  Getopt::Complete verifies that the option values 
specified match their own completion list, and will otherwise add additional errors
explaining the problem.

The %ARGS hash is an alias for %Getopt::Complete::ARGS.  The alias is not created 
in the caller's namespaces if a hash named %ARGS already exists with data, but
the results are always available from %Getopt::Complete::ARGS.

They keys of the hash are the option names, minus any specifiers like "=s" or "!".
The key is only present if the option was specified on the command-line.

The values of the hash are the values from the command-line.  For multi-value
options the hash value is an arrayref.

=head1 OBJECT API

An object $ARGS is also created in the namespace (class L<Getopt::Complete::Args>)
with a more detailed API.  See the documentation for that module, and 
L<Getopt::Complete::Options> for details.

It is possible to override any part of the default process, including doing custom 
parsing, doing processing at run-time, and and preventing exit when there are errors.

See OVERRIDING COMPILE-TIME OPTION PARSING for more information. 

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

Subsequent code can use %ARGS instead of doing any futher options
parsing.  

Existing apps can have their call to Getopt::Long converted
into "use Getopt::Complete".  If you bind variables directly
the code would need to be updated to get values from the %ARGS hash.

=item 2

Put the following in your .bashrc or .bash_profile:

  complete -C myprogram myprogram

For the very conservative, do this (to ensure nothing runs during completion checks):
 
  complete -C 'perl -c myprogram 2>/dev/null' myprogram

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

See below for details on how to permit values which aren't shown in completions to
be used and not generate errors.

=item undef 

An undefined value indicates that the option is not completable.  No completions
will be offered by the application, though any value provided by the user will be
considered valid.

Note that this is distinct from returning an empty arrayref returned from a callback, 
which implies that there ARE known completions but the user has failed to match any of them.

Also note: this is the only valid completion for boolean parameters, since there is no 
value to specify on the command-line.

  use Getopt::Complete (
    'name'      => undef,   # take --name "anyting" 
    'perky!'    => undef,   # take --perky or --no-perky
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
GetOptions(\%h, @specification) to produce the %ARGS hash.  Customization of
Getopt::Long should occur in a BEGIN block before using Getopt::Complete.  

=head1 DEVELOPMENT

Patches are welcome.
 
 http://github.com/sakoht/Getopt--Complete-for-Perl/

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

