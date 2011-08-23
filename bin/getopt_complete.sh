#!/usr/bin/env bash

# You need to add a completion handler to Bash in your .bashrc, e.g.:
#   complete -F _getopt_complete your_cmd
function _getopt_complete () {
    COMPREPLY=($( COMP_CWORD=$COMP_CWORD perl `which ${COMP_WORDS[0]}` ${COMP_WORDS[@]:0} ));
}
