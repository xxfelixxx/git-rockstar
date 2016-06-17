git-rockstar
==================

Graph all git contributions over time to find your rockstars!

[![Build Status](https://secure.travis-ci.org/xxfelixxx/git-rockstar.svg)](http://travis-ci.org/xxfelixxx/git-rockstar)

Name
-----
Git Rockstar

Version
---------
Version 0.2

Examples
-----------

    $ git clone git@github.com:Perl/perl5

    $ git-rockstar perl5

[perl5 rockstars](https://github.com/xxfelixxx/git-rockstar/blob/master/images/perl5_rockstar.svg)

-----------

    $ git clone git@github.com:JuliaLang/julia

    $ git-rockstar julia

[julia rockstars](https://github.com/xxfelixxx/git-rockstar/blob/master/images/julia_rockstar.svg)

-----------

    $ git clone git@github.com:emacs-mirror/emacs

    $ git-rockstar emacs

[emacs rockstars](https://github.com/xxfelixxx/git-rockstar/blob/master/images/emacs_rockstar.svg)

Configuration
---------------

    Add a file named .git-rockstar to the top level of your git repo.
    The contents are JSON with the following fields:

        ignore-dir          : a list of paths
                              "foo" will ignore foo/bar/baz but not bar/baz/foo

        ignore-file-pattern : a list of patterns
                              files matching pattern will be skipped

        ignore-revert       : 1 or 0, default is to ignore revert changes

        author-alias        : key/value pairs
                              attribute various author aliases to one user

        authors-to-skip     : a list of authors to ignore
                              useful to filter out auto-commits and build commits

.git-rockstar-example
-----------------------

    {
        "ignore-dir" : [ "test", "build" ],
        "ignore-file-pattern" : [ ".bak", "~" ],
        "ignore-revert" : "1",
        "author-alias" : {
                "Linus" : "Linus Torvalds",
                "linus" : "Linus Torvalds",
                "larry" : "Larry Wall",
        },
        "authors-to-skip" : [ "robot_user", "auto_commit_user" ]
    }

