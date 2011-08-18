#!/usr/bin/env bash

function _getopt_complete () {
    COMPREPLY=($( COMP_CWORD=$COMP_CWORD perl `which ${COMP_WORDS[0]}` ${COMP_WORDS[@]:0} ));
}
