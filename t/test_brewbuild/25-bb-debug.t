#!/usr/bin/perl
use strict;
use warnings;

use Archive::Extract;
use File::Path qw(remove_tree);
use Test::BrewBuild;
use Test::More;

if (! $ENV{BBDEV_TESTING}){
    plan skip_all => "developer tests only";
    exit;
}
if ($^O =~ /MSWin/) {
    plan skip_all => "skip debug tests on windows";
    exit;
}
{ # -d 7

    my $ae = Archive::Extract->new(archive => 't/modules/bb-pass.zip');
    $ae->extract(to => '.');

    chdir 'BB-Pass';
    `brewbuild -r`;
    my $ret = `brewbuild -d 7`;
    chdir '..';

    my @res = split /\n/, $ret;
    @res = grep /\S/, @res;

    my $file = $^O =~ /MSWin/
        ? 't/base/115-level7_win.data'
        : 't/base/115-level7.data';

    open my $fh, '<', $file or die $!;

    my @base = <$fh>;
    close $fh;
    @base = grep /\S/, @base;

    ok (@res > 30, "-d 7 proper line count");

    remove_tree('BB-Pass');
    is (-d 'BB-Pass', undef, "-d 7 dir removed ok");
}
{ # --debug 6

    my $ae = Archive::Extract->new(archive => 't/modules/bb-pass.zip');
    $ae->extract(to => '.');

    chdir 'BB-Pass';
    `brewbuild -r`;
    my $ret = `brewbuild --debug 6`;
    chdir '..';

    my @res = split /\n/, $ret;
    @res = grep /\S/, @res;

    my $file = $^O =~ /MSWin/
        ? 't/base/115-level6_win.data'
        : 't/base/115-level6.data';

    open my $fh, '<', $file or die $!;
    my @base = <$fh>;
    close $fh;
    @base = grep /\S/, @base;

    ok (@res > 16, "--devel 6 proper line count");

    remove_tree('BB-Pass');
    is (-d 'BB-Pass', undef, "--devel 6 dir removed ok");
}

done_testing();

