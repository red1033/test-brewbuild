#!/usr/bin/perl
use strict;
use warnings;

use Capture::Tiny qw(:all);
use Cwd;
use Test::BrewBuild::Dispatch;
use Test::BrewBuild::Tester;
use Test::More tests => 1;

if (! $ENV{BBDEV_TESTING}){
    plan skip_all => "developer tests only";
    exit;
}

my $t = Test::BrewBuild::Tester->new;
$t->start;

my $d = Test::BrewBuild::Dispatch->new;

eval {
    my ($out, $err) = capture {
        $d->dispatch(
            testers => [ qw(127.0.0.1:7800) ],
        );
    };
    like ($out, qr/no repository supplied/, "Dispatch dies if repo can't be found");
};

$t->stop;
