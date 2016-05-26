erl_libutil
=====

A general purpose OTP library to be used by other projects:
* recursive_search: Recursively traverse one or more directory trees.

Eventually, its content should grow.  For more information, generate edoc:

    $ rebar3 edoc

Build
-----

    $ rebar3 dialyzer
    $ rebar3 compile
    $ rebar3 shell

Usage
-----

    %% Find all directories under /usr/local/share/, whose names end with a ".git " suffix
    GitBareRepositories = recursive_search:find_by_name(["/usr/local/share"], ".git$", dir).

    %% Find only files, containing "needle" within the filename, under /etc/ or /usr/local/haystack/
    NeedleFiles = recursive_search:find_by_name(["/usr/local/haystack", "/etc"], "needle", file).

    %% Find files or directories, with "needle" as part of the filename
    Needles = recursive_search:find_by_name(["/"], "needle", any).
