#!/usr/bin/perl
use strict;
use warnings;

use Capture::Tiny qw(capture_stdout);
use Test::BrewBuild::Dispatch;
use Test::More;

if (! $ENV{BBDEV_TESTING}){
    plan skip_all => "developer tests only";
    exit;
}
my $d = Test::BrewBuild::Dispatch->new;

my $warn = capture_stdout {
    $d->dispatch(
        'asdf',
        'https://stevieb9@github.com/stevieb9/mock-sub',
        [ qw(127.0.0.1:7800) ],
    );

};

like ($warn, qr/error: only brewbuild/, "bad command dies");

done_testing();