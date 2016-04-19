package Test::BrewBuild::BrewCommands;
use strict;
use warnings;

use version;

our $VERSION = '1.05_02';

my $log;

sub new {
    my ($class, $plog) = @_;

    my $self = bless {}, $class;

    $self->{log} = $plog->child('Test::BrewBuild::BrewCommands');
    $log = $self->{log};
    $log->_6("constructing new Test::BrewBuild::BrewCommands object");

    $self->brew;

    return $self;
}
sub brew {
    my $self = shift;

    return $self->{brew} if $self->{brew};

    my $brew;

    if ($self->is_win){
        my $exe_loc = `where berrybrew.exe`;
        $brew = (split /\n/, $exe_loc)[0];
    }
    else {
        $brew = 'perlbrew';
    }

    $log->child('brew')->_6("*brew cmd is: $brew");
    $self->{brew} = $brew;

    return $brew;
}
sub info {
    my $self = shift;
    return $self->is_win
        ? `$self->{brew} available 2>nul`
        : `perlbrew available 2>/dev/null`;
}
sub installed {
    my ($self, $legacy, $info) = @_;

    $log->child('installed')->_6("cleaning up perls installed");

    return if ! $info;

    my @installed = $self->is_win
        ? $info =~ /(\d\.\d{2}\.\d(?:_\d{2}))(?!=_)\s+\[installed\]/ig
        : $info =~ /i.*?(perl-\d\.\d+\.\d+)/g;

    if (! $legacy){
        @installed = grep { /^(?:perl-)?\d\.(\d+)/; $1 >= 8 } @installed;
    }

    return @installed;

}
sub using {
    my ($self, $info) = @_;

    $log->child( 'using' )->_6( "checking for which ver we're using" );

    if ($self->is_win) {
        my @installed = $info =~ /(\d\.\d{2}\.\d(?:_\d{2}))(?!=_)\s+\[installed\]\*/ig;
        return $installed[0];
    }
    else {
        my $using = version->parse($])->normal;
        $using =~ s/v//;
        $using = "perl-$using";
        return $using;
    }
}
sub available {
    my ($self, $legacy, $info) = @_;

    $log->child('available')->_6("determining available perls");

    my @avail = $self->is_win
        ? $info =~ /(\d\.\d+\.\d+_\d+)/g
        : $info =~ /(perl-\d\.\d+\.\d+)/g;

    if (! $legacy){
        @avail = grep { /^(?:perl-)?\d\.(\d+)/; $1 > 8 } @avail;
    }
    return @avail;
}
sub install {
    my $self = shift;

    my $install_cmd = $self->is_win
        ? "$self->{brew} install"
        : 'perlbrew install --notest -j 4';

    $log->child('install')->_6("install cmd is: $install_cmd");

    return $install_cmd;
}
sub remove {
    my $self = shift;

    my $remove_cmd = $self->is_win
        ? "$self->{brew} remove"
        : 'perlbrew uninstall';

    $log->child('remove')->_6("remove cmd is: $remove_cmd");

    return $remove_cmd;
}
sub is_win {
    my $is_win = ($^O =~ /Win/) ? 1 : 0;
    return $is_win;
}

1;

=head1 NAME

Test::BrewBuild::BrewCommands - Provides Windows/Unix *brew command
translations for Test::BrewBuild

=head1 METHODS

=head2 new

Returns a new Test::BrewBuild::BrewCommands object.

=head2 brew

Returns C<perlbrew> if on Unix, and the full executable path for
C<berrybrew.exe> if on Windows.

=head2 info

Returns the string result of C<*brew available>.

=head2 installed($info)

Takes the output of C<*brew available> in a string form. Returns the currently
installed versions, formatted in a platform specific manner.

=head2 using($info)

Returns the current version of perl we're using. C<$info> is the output from
C<info()>.

=head2 available($legacy, $info)

Similar to C<installed()>, but returns all perls available. If C<$legacy> is
false, we'll only return C<perl> versions C<5.8.0+>.

=head2 install

Returns the current OS's specific C<*brew install> command.

=head2 remove

Returns the current OS's specific C<*brew remove> command.

=head2 is_win

Returns 0 if on Unix, and 1 if on Windows.

=head1 AUTHOR

Steve Bertrand, C<< <steveb at cpan.org> >>

=head1 CONTRIBUTING

Any and all feedback and help is appreciated. A Pull Request is the preferred
method of receiving changes (L<https://github.com/stevieb9/p5-test-brewbuild>),
but regular patches through the bug tracker, or even just email discussions are
welcomed.

=head1 BUGS

L<https://github.com/stevieb9/p5-test-brewbuild/issues>

=head1 LICENSE AND COPYRIGHT

Copyright 2016 Steve Bertrand.

This program is free software; you can redistribute it and/or modify it
under the terms of either: the GNU General Public License as published
by the Free Software Foundation; or the Artistic License.

See L<http://dev.perl.org/licenses/> for more information.


=cut
 
