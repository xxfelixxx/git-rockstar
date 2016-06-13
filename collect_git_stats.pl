#!/usr/bin/env perl

use warnings;
use strict;
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
my ($master_branch) = $head =~ m|^.*-> (\w+)\s*$|;

# IN MASTER
my $cmd = 'git log ' . $master_branch . ' --no-merges --numstat --date=short|';
open my $fh, $cmd
    or die "Unable to run '$cmd' : $!";

my ($author, $date, $data);
my $record = '';
my $count = 0;
while (<$fh>) {
    chomp();
    if (m|^commit |) {
        process_in_master($record);
        # Start of new record
        $record = '';
    }
    $record .= $_ . "\n";
    warn '.' if ($count++ % 100 == 0);
}
close $fh;
process_in_master($record); # Last one

# NOT IN MASTER
$cmd = 'git rev-list --all --not ' . $master_branch . ' --no-merges | xargs -L1 git log -n1 --numstat --date=short |';
open $fh, $cmd
    or die "Unable to run '$cmd' : $!";

$count = 0;
while (<$fh>) {
    chomp();
    if (m|^commit |) {
        process_not_in_master($record);
        # Start of new record
        $record = '';
    }
    $record .= $_ . "\n";
    warn '.' if ($count++ % 100 == 0);
}
close $fh;
process_not_in_master($record); # Last one

print join "\t", 'author', 'date', 'changes_in_master', 'changes_not_in_master',
    'total_in_master', 'total_not_in_master', 'total', 'percent_in_master';
print "\n";
for my $author ( sort keys %$data ) {
    my $d = $data->{$author};
    my $total_in_master = 0;
    my $total_not_in_master = 0;
    my $total = 0;
    my $percent_in_master = 0;
    for my $date (uniq sort (keys %{$d->{master}}, keys %{$d->{not_master}})) {
        my $master     = $d->{master}->{$date} || 0;
        my $not_master = $d->{not_master}->{$date} || 0;
        $total_in_master += $master;
        $total_not_in_master += $not_master;
        $total += $master;
        $total += $not_master;
        if ($total == 0) {
            $percent_in_master = 0;
        } else {
            $percent_in_master = int ( $total_in_master / $total * 100 );
        }
        print join "\t", $author, $date,$master, $not_master, $total_in_master, $total_not_in_master, $total, $percent_in_master;
        print "\n";
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
            $data->{$real_author}->{master}->{$date} += $changes;
        } else {
            $data->{$real_author}->{not_master}->{$date} += $changes;
        }
    }
}

my $authors = {};
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
