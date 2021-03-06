#!/usr/bin/env perl

use warnings;
use strict;
use File::Temp;
use List::MoreUtils qw( any uniq );
use JSON qw( decode_json );

my ($repo_dir) = $ARGV[0];
$repo_dir or usage();
-d $repo_dir or die "Invalid directory '$repo_dir'";

chdir $repo_dir;

chomp(my ($git_repo) = qx( git rev-parse --show-toplevel ));
-d $git_repo or usage();

chdir $git_repo;

my $config = $ARGV[1] || join('/',$git_repo, '.git-rockstar');
my $config_data = parse_config( $config );

chomp(my $head = `git branch -r | grep origin/HEAD`);
#   origin/HEAD -> origin/master
my ($master_branch) = $head =~ m|^.*->\s+(\S+)\s*$|; # Branch names cannot have spaces
defined $master_branch
    or die "Unable to grok master branch name from '$head' : $master_branch";

my $authors = {};
my ($author, $date, $data);

collect_master_data();
collect_not_in_master_data();
print_summary_data();
exit 0;

sub collect_master_data {
    my $cmd = 'git log ' . $master_branch . ' --no-merges --numstat --date=short|';
    collect_data($cmd, \&process_in_master);
}

sub collect_not_in_master_data {
    my $commits = File::Temp->new();
    my $cmd = 'git rev-list --all --not ' . $master_branch . ' --no-merges >' . $commits;
    (system($cmd) == 0)
        or die "Unable to run '$cmd' : $!";

    if ( -s $commits ) {
        # We have non-master commits
        $cmd = 'cat ' . $commits . ' | xargs -L1 git log -n1 --numstat --date=short |';
        collect_data($cmd, \&process_not_in_master);
        unlink $commits
            or die "Unable to unlink $commits : $!";
    } else {
        warn "There are no non-master commits to process!";
    }
}

sub collect_data {
    my ($cmd, $processing_function) = @_;
    open my $fh, $cmd
        or die "Unable to run '$cmd' : $!";

    my $record = '';
    my $count = 0;
    while (<$fh>) {
        chomp();
        if (m|^commit |) {
            $processing_function->($record);
            # Start of new record
            $record = '';
            $count++;
        }
        $record .= $_ . "\n";
        warn '.' if ($count % 100 == 0);
    }
    close $fh;
    $processing_function->($record); # Last one
}

sub print_summary_data {

    print join "\t", 'author', 'date', 'changes_in_master', 'changes_not_in_master',
        'total_changes_in_master', 'total_changes_not_in_master', 'total_changes',
        'percent_changes_in_master', 'commits_in_master', 'commits_not_in_master',
        'total_commits_in_master', 'total_commits_not_in_master', 'total_commits';
    print "\n";
    for my $author ( sort keys %$data ) {
        my $d = $data->{$author};
        my $total_changes_in_master = 0;
        my $total_changes_not_in_master = 0;
        my $total_commits_in_master = 0;
        my $total_commits_not_in_master = 0;
        my $total_commits = 0;
        my $total_changes = 0;
        my $percent_in_master = 0;
        for my $date (uniq sort (keys %{$d->{master}}, keys %{$d->{not_master}})) {
            my $master_changes     = $d->{master}->{$date}->{changes}     || 0;
            my $master_commits     = $d->{master}->{$date}->{commits}     || 0;

            my $not_master_changes = $d->{not_master}->{$date}->{changes} || 0;
            my $not_master_commits = $d->{not_master}->{$date}->{commits} || 0;

            $total_commits_in_master     += $master_commits;
            $total_commits_not_in_master += $not_master_commits;
            $total_commits               += $master_commits + $not_master_commits;

            $total_changes_in_master     += $master_changes;
            $total_changes_not_in_master += $not_master_changes;
            $total_changes               += $master_changes + $not_master_changes;

            if ($total_changes == 0) {
                $percent_in_master = 0;
            } else {
                $percent_in_master = int ( $total_changes_in_master / $total_changes * 100 );
            }
            print join "\t", $author, $date, $master_changes, $not_master_changes, $total_changes_in_master, $total_changes_not_in_master, $total_changes, $percent_in_master, $master_commits, $not_master_commits, $total_commits_in_master, $total_commits_not_in_master, $total_commits;
            print "\n";
        }
    }
}

sub process_in_master {
    my ($record) = @_;
    process($record,1);
}

sub process_not_in_master {
    my ($record) = @_;
    process($record,0);
}

sub process {
    my ($record, $is_merged) = @_;
    return unless $record;
    $record =~ s|\s*$||s;
    my ($commit) = $record =~ m|^commit (\w+)|;
    $commit or die "No commit!\n$record";
    my ($author) = $record =~ m|Author: (.+?) <|s;
    $author or die "No author!\n$record";
    my $real_author = get_real($author);
    my ($date) = $record =~ m|Date:\s+(\d+-\d+-\d+)|s;
    $date or die "No date!\n$record";
    return if $date eq '1970-01-01'; # unix 0 time, clearly a mistake somewhere
    my $ignore_dirs = $config_data->{"ignore-dir"} || [];
    my $ignore_file_patterns = $config_data->{"ignore-file-pattern"} || [];
    my $ignore_revert = $config_data->{"ignore-revert"} || 1; # default is to ignore
    my $authors_to_skip = $config_data->{"authors-to-skip"} || [];
    return if any { $_ eq $author } @$authors_to_skip;
    for my $line ( split /\n/, $record ) {
        next unless $line =~ m|^(\d+)\s+(\d+)\s+(\S+)|;
        my ($adds, $deletes, $filename) = ($1, $2, $3);
        next if any { $filename =~ m|^$_| } @$ignore_dirs;
        next if any { $filename =~ m|$_|  } @$ignore_file_patterns;

        my $changes = $adds + $deletes;
        if ($ignore_revert and $record =~ m|This reverts|s) {
            $changes = 0;
        }

        if ($changes > 50000) {
            warn $record;
            #die;
        }

        if ($is_merged) {
            $data->{$real_author}->{master}->{$date}->{changes} += $changes;
        } else {
            $data->{$real_author}->{not_master}->{$date}->{changes} += $changes;
        }
    }

    if ($is_merged) {
        $data->{$real_author}->{master}->{$date}->{commits} += 1;
    } else {
        $data->{$real_author}->{not_master}->{$date}->{commits} += 1;
    }
}

sub get_real {
    my ($author) = @_;
    
    $authors ||= $config_data->{"author-alias"} || {};

    return $authors->{$author} || $author;
}

sub usage {
    print "Collect git daily commit summaries for all contributors.\n\n";
    print "usage: $0 git_repo_dir [ /path/to/.git-rockstar ]\n";
    exit 0;
}

sub parse_config {
    my ($config) = @_;

    my $config_data = {};
    if (-f $config) {
        open my $fh, "<$config" or die "Unable to read '$config' : $!";
        my ($json) = do { local $/; <$fh> }; # Slurp
        close $fh;
        eval {
            $config_data = decode_json($json);
        };
        if ($@) {
            die "Unable to parse '$config' as valid json : $@";
        }
    }

    return validate_config( $config_data );
}

sub validate_config {
    my ($config_data) = @_;

    my $key_type_map = {
        'ignore-dir'          => { type => 'ARRAY' },
        'ignore-file-pattern' => { type => 'ARRAY' },
        'ignore-revert'       => { type => ''      },
        'author-alias'        => { type => 'HASH'  },
        'authors-to-skip'     => { type => 'ARRAY' },
    };

    my $validated_config = {};
    for my $key ( keys %$key_type_map ) {
        next unless defined $config_data->{$key};
        my $type_config = ref $config_data->{$key};
        my $type_desired = $key_type_map->{$key}->{type};
        if ( $type_config eq $type_desired ) {
            $validated_config->{$key} = $config_data->{$key};
        } else {
            die "Invalid field '$key' should be " . $type_desired || 'scalar value';
        }
    }

    return $validated_config;

}
