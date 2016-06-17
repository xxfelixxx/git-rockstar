#!/usr/bin/env perl

use warnings;
use strict;

use File::Temp;
use Test::More;
my $script_name = 'collect_git_stats.pl';

chomp( my ($top_level) = qx( git rev-parse --show-toplevel ) );
ok( defined $top_level, "Found git repo toplevel : $top_level" )
    or BAIL_OUT("Cannot find git repo toplevel!");
my $collect_git_stats = join('/', $top_level, $script_name );
ok( -f $collect_git_stats, "Found $script_name script : $collect_git_stats" )
    or BAIL_OUT("Cannot find $script_name script");

my $tmp_output = File::Temp->new();
my $tmp_error = File::Temp->new();
my $data = {};

main();
done_testing();
exit 0;

sub main {
    compile_check();
    run_collect_git_stats();
    total_commit_check();
}

sub run_collect_git_stats {
    my $cmd = "$collect_git_stats $top_level > $tmp_output 2> $tmp_error";
    my $result = system($cmd);
    ok( $result == 0, "Ran $script_name on $top_level" )
        or BAIL_OUT("Could not run $script_name on $top_level : $!");
    open my $fh, $tmp_output
        or die "Unable to open $tmp_output for reading : $!";
    my @headers;
    while( <$fh> ) {
        chomp();
        if( $. == 1 ) {
            @headers = split /\t/;
            next;
        }
        my @fields = split /\t/;
        if (scalar(@headers) != scalar(@fields)) {
            fail("Invalid line: '$_'");
        } else {
            my $author = $fields[0];
            my $date   = $fields[1];
            my $row_data = {};
            for my $ii ( 2 .. $#headers ) {
                $row_data->{ $headers[ $ii ] } = $fields[ $ii ];
            }
            $data->{$author}->{$date} = $row_data;
        }
    }
    my $n_authors = (scalar keys %$data) || 0;

    ok( $n_authors, "Found $n_authors authors in the git repo $top_level")
        or BAIL_OUT("Processing failed!");
}

sub compile_check {
    my $cmd = "/usr/bin/env perl -cwT $collect_git_stats " . '2>&1';
    my $result = qx($cmd);
    ok( $result =~ m|syntax OK|, "Compile Check '$cmd'" )
        or BAIL_OUT("Compile Errors:\n $result");
}

sub total_commit_check {
    my $cmd = 'git log --all --no-merges | egrep "^commit \w{40}" | wc -l';
    chomp( my ($count) = qx($cmd) );
    my $total_commits = 0;
    for my $author ( keys %$data ) {
        my @commits = author_field_vector( $author, 'total_commits' );
        $total_commits += pop @commits; # Get last (most recent) value
    }
    my $count_travis = $ENV{TRAVIS_GIT_COMMITS};
    if ( defined $count_travis ) {
        note("Running under Travis-CI, there should be <= $count_travis total commits");
    }

    ok( $count == $total_commits, "Total Commits [ $count ] For All Authors is Correct" )
        or diag("Expected $count commits, but got $total_commits instead");
}

sub author_field_vector {
    my ($author, $field) = @_;
    my @results;
    my @dates = keys %{ $data->{$author} };
    for my $date ( sort @dates ) {
        push @results, $data->{$author}->{$date}->{$field};
    }
    return @results
}

1;
