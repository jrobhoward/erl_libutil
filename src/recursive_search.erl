%%% -*- Mode: Erlang; fill-column: 75; comment-column: 50; -*-
%%% -------------------------------------------------------------------
%%%
%%% Copyright (c) 2016 James Howard (jrobhoward@gmail.com)
%%%
%%% This file is provided to you under the Apache License,
%%% Version 2.0 (the "License"); you may not use this file
%%% except in compliance with the License.  You may obtain
%%% a copy of the License at
%%%
%%%   http://www.apache.org/licenses/LICENSE-2.0
%%%
%%% Unless required by applicable law or agreed to in writing,
%%% software distributed under the License is distributed on an
%%% "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
%%% KIND, either express or implied.  See the License for the
%%% specific language governing permissions and limitations
%%% under the License.
%%%
%%% -------------------------------------------------------------------

%% ----------------------------------
%% @doc Recursively traverse one or more directory trees.
%%
%% Presently there is a single exported function that generates a list of files or directories.
%%
%% It was written with UNIX (FreeBSD) in mind, but should work on Linux, Windows, or OS X.
%%
%% This module makes a best-effort to handle symlinks properly:
%%   <li>Symlinks pointing to directories are traversed.</li>
%%   <li>Symlinks pointing to files are honored.</li>
%%   <li>Symlink (names) also participate in regex matching.</li>
%%   <li>Each file only gets reported once (regardless of the number of symbolic/hard links).</li>
%%
%% There are a some notable limitations:
%%   <li>Although each file only gets reported once (in the presence of multiple hard/symbolic
%%      links), <em>which</em> file path gets reported is undefined.</li>
%%   <li>Efficiency is good, but not great.  It's written in pure Erlang, uses additional memory,
%%      and performs additional disk IO (i.e. more than minimum necessary).  If you have slow disk
%%      or over 100K directires to traverse, forking a native process may perform better.</li>
%%
%% Examples:
%% ```
%% %% Find all directories under /usr/local/share/, whose names end with a ".git" suffix
%% GitBareRepositories = recursive_search:find_by_name(["/usr/local/share"], ".git$", dir).
%%
%% %% Find only files, containing "needle" within the filename, under /etc/ or /usr/local/haystack/
%% NeedleFiles = recursive_search:find_by_name(["/usr/local/haystack", "/etc"], "needle", file).
%%
%% %% Find files or directories, with "needle" as part of the filename
%% Needles = recursive_search:find_by_name(["/"], "needle", any).
%% '''
%%
%% ----------------------------------
-module(recursive_search).
-export([find_by_name/3]).

-include_lib("kernel/include/file.hrl").


%% @doc Recursively traverse directories of DirList for names matching supplied regex RegExpStr.
-type dirname() :: file:name().
-type filetype() :: dir|file|any.
-spec find_by_name(DirList, RegExpStr, FileType) -> DirList when
      DirList :: [dirname()],
      RegExpStr :: string(),
      FileType :: filetype().
find_by_name(DirList, RegExpStr, FileType) ->
    {ok, RegExp} = re:compile(RegExpStr,[unicode]),
    find_by_name(DirList, RegExp, FileType, maps:new(), maps:new()).

find_by_name([], _RegExp, _FileType, _TraversedDirectories, Matches) ->
    lists:sort(maps:values(Matches));
find_by_name(DirList, RegExp, FileType, TraversedDirectories, Matches) ->

    %% extract head of list, assert it's a directory (or symlink pointing to dir)
    [DirName| DirListTail] = DirList,
    true = filelib:is_dir(DirName),

    %% keep track of visited directory, doing so to avoid infinite loops
    {ok, FileInfo} = file:read_file_info(DirName),
    DirInfo = {
      FileInfo#file_info.major_device,
      FileInfo#file_info.minor_device,
      FileInfo#file_info.inode},
    NewTraversedDirectories = maps:put(DirInfo, DirName, TraversedDirectories),

    %% fetch listing of current directory, make note of unvisited subdirectories
    CurrentDirListing = case file:list_dir(DirName) of
                            {ok, DirListing} -> DirListing;
                            {error, _} -> []
                        end,
    FilePaths = [filename:join(DirName, Name) || Name <- CurrentDirListing],
    DirsOnly = lists:filter(fun(F) -> filelib:is_dir(F) end, FilePaths),
    NewDirsOnly = lists:filter(fun(D) ->
                                       {ok, Finfo} = file:read_file_info(D),
                                       Dinfo = {
                                         Finfo#file_info.major_device,
                                         Finfo#file_info.minor_device,
                                         Finfo#file_info.inode},
                                       not maps:is_key(Dinfo, NewTraversedDirectories)
                               end,
                               DirsOnly),
    NewDirList = lists:append(DirListTail, NewDirsOnly),

    %% check directory listing for regex matches, include DirName as a potential match
    SearchSet = case FileType of
                    dir -> [DirName | DirsOnly];
                    file -> lists:filter(fun(F) -> filelib:is_regular(F) end, FilePaths);
                    any -> [DirName | lists:filter(fun(F) -> filelib:is_file(F) end, FilePaths)]
                end,
    AdditionalMatches = lists:foldl(fun(F, Acc) ->
                                            RetVal = case re:run(F, RegExp, [{capture, none}]) of
                                                         match ->
                                                             {ok, Finfo} = file:read_file_info(F),
                                                             Dinfo = {
                                                               Finfo#file_info.major_device,
                                                               Finfo#file_info.minor_device,
                                                               Finfo#file_info.inode},
                                                             maps:put(Dinfo, F, Acc);
                                                         nomatch -> Acc
                                                     end,
                                            RetVal
                                    end,
                                    maps:new(),
                                    SearchSet),
    find_by_name(NewDirList, RegExp, FileType, NewTraversedDirectories, maps:merge(Matches, AdditionalMatches)).
