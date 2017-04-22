package Test::BrewBuild::Tester;
use strict;
use warnings;

use Carp qw(croak);
use Config;
use Cwd qw(getcwd);
use File::Path qw(remove_tree);
use IO::Socket::INET;
use Logging::Simple;
use Proc::Background;
use Storable;
use Test::BrewBuild;
use Test::BrewBuild::Git;

our $VERSION = '2.17';

$| = 1;

my $log;

sub new {
    my ($class, %args) = @_;
    my $self = bless {}, $class;

    $self->{log_to_stdout} = defined $args{stdout} ? $args{stdout} : 0;
    $self->{logfile} = $args{logfile};

    $self->{auto} = $args{auto};
    $self->{csum} = $args{csum};

    $log = Logging::Simple->new(level => 0, name => 'Tester');

    my $log_file = \$self->{log};

    if ($self->{logfile}){
        $log_file = Test::BrewBuild->workdir ."/bbtester_parent.log";
        $log->_7("log file is: $log_file");
    }

    if ($self->{log_to_stdout}){
        $log->_7("logging to STDOUT");
        $log->file($log_file);
    }

    if (defined $args{debug}){
        $log->level($args{debug}) if defined $args{debug};
        $self->{debug} = $args{debug};
    }

    my $log = $log->child('new');
    $log->_5("instantiating new Test::BrewBuild::Tester object");

    $self->_config;
    $self->_pid_file;

    return $self;
}
sub start {
    my $self = shift;

    my $log = $log->child("start");
    my $pid_file = $self->_pid_file;

    if ($self->status){
        my $fh;
        open $fh, '<', $pid_file or croak $!;
        my $existing_pid = <$fh>;
        close $fh;

        if ($existing_pid){
            if (kill(0, $existing_pid)){
                $log->_0("tester is already running at PID $existing_pid");
                croak "\nTest::BrewBuild test server already running " .
                    "on PID $existing_pid...\n\n";
            }
        }
    }

    my ($perl, @args);
    my $work_dir = Test::BrewBuild->workdir;

    if ($^O =~ /MSWin/){
        $log->_6("on Windows, using work dir $work_dir");

        my $t;

        for (split /;/, $ENV{PATH}){
            if (-x "$_/perl.exe"){
                $perl = "$_/perl.exe";
                last;
            }
        }
        for (split /;/, $ENV{PATH}){
            if (-e "$_/bbtester"){
                $t = "$_/bbtester";
                last;
            }
        }
        $log->_6("using command: $perl $t --fg");

        @args = ($t, '--fg');
    }
    else {
        $log->_6("on Unix, using work dir $work_dir");

        $perl = 'perl';
        @args = qw(bbtester --fg);

        $log->_6("using command: bbtester --fg");
    }

    if (defined $self->{auto}){
        push @args, ('--auto', $self->{auto});
        push @args, ('--csum', $self->{csum}) if defined $self->{csum};

    }
    if (defined $self->{debug}){
        push @args, ('--debug', $self->{debug});
    }
    if ($self->{logfile}){
        push @args, ('--logfile');
    }

    mkdir $work_dir or croak "can't create $work_dir dir: $!" if ! -d $work_dir;
    chdir $work_dir or croak "can't change to dir $work_dir: $!";
    $log->_7("chdir to: ".getcwd());

    my $bg;

    if ($^O =~ /MSWin/){
        $bg = Proc::Background->new($perl, @args);
    }
    else {
        $bg = Proc::Background->new(@args);
    }

    my $pid = $bg->pid;

    my $ip = $self->ip;
    my $port = $self->port;

    $log->_5("Started the BB test server at PID $pid on IP $ip and port $port");

    print "\nStarted the Test::BrewBuild test server at PID $pid on IP " .
      "address $ip and TCP port $port...\n\n";

    open my $wfh, '>', $pid_file or croak $!;
    print $wfh $pid;
    close $wfh;

    # error check for bbtester

    if ($self->status){
        sleep 1;
        my $fh;
        open $fh, '<', $pid_file or croak $!;
        my $existing_pid = <$fh>;
        close $fh;

        if ($existing_pid){
            if (! kill(0, $existing_pid)){
                $log->_0("error! run bbtester --fg at the CLI and check for " .
                         "failure"
                );
                croak "\nerror! run bbtester --fg at the command line and " .
                    "check for failure\n\n";
            }
        }
    }
}
sub stop {
    my $self = shift;

    my $log = $log->child("stop");

    $log->_5("attempting to stop the tester service");

    if (! $self->status) {
        $log->_5("Test::BrewBuild test server is not running");
        print "\nTest::BrewBuild test server is not running...\n\n";
        return;
    }

    my $pid_file = $self->_pid_file;

    open my $fh, '<', $pid_file or croak $!;
    my $pid = <$fh>;
    close $fh;
    $log->_5("Stopping the BB test server at PID $pid");
    print "\nStopping the Test::BrewBuild test server at PID $pid...\n\n";
    kill 'KILL', $pid;
    unlink $pid_file;
}
sub status {
    my $self = shift;
    my $log = $log->child("status");
    my $pid_file = $self->_pid_file;
    my $status = -f $pid_file ? 1 : 0;
    $log->_6("test server status: $status");
    return $status;
}
sub listen {
    my $self = shift;
    my $log = $log->child("listen");

    my $log_file = \$self->{log};
    if ($self->{logfile}){
       $log_file = Test::BrewBuild->workdir ."/bbtester_child.log";
    }
    $log->file($log_file) if ! $self->{log_to_stdout};

    my $sock = new IO::Socket::INET (
        LocalHost => $self->ip,
        LocalPort => $self->port,
        Proto => 'tcp',
        Listen => 5,
        Reuse => 1,
    );
    croak "cannot create socket $!\n" unless $sock;

    $log->_6("successfully created network socket on IP $self->{ip} and port " .
             "$self->{port}"
    );

    while (1){

        my $work_dir = Test::BrewBuild->workdir;
        mkdir $work_dir if ! -d $work_dir;
        chdir $work_dir;
        $log->_7("work dir is: $work_dir");
        $log->_7("chdir to work dir: ".getcwd());

        my $res = {
            platform => $Config{archname},
        };

        $log->_7("platform: $res->{platform}");

        my $dispatch = $sock->accept;

        $log->_7("now accepting incoming connections");

        # ack
        my $ack;
        $dispatch->recv($ack, 1024);

        $log->_7("received ack: $ack");

        $dispatch->send($ack);

        $log->_7("returned ack: $ack");

        my $cmd;
        $dispatch->recv($cmd, 1024);
        $res->{cmd} = $cmd;

        $log->_7("received cmd: $res->{cmd}");

        my @args = split /\s+/, $cmd;

        if ($args[0] ne 'brewbuild'){
            my $err = "error: only 'brewbuild' is allowed as a command. ";
            $err .= "you sent in: " . join ' ', @args;
            $log->_0($err);
            $dispatch->send($err);
            next;
        }
        my $unsafe_args = _unsafe_args();

        for my $unsafe_arg (@$unsafe_args){
            if (grep /\Q$unsafe_arg\E/, @args){
                croak "'$unsafe_arg' is an invalid argument to brewbuild. " .
                      "Can't continue...\n";
            }
        }

        shift @args;
        $log->_7("sending 'ok'");
        $dispatch->send('ok');

        my $repo = '';
        $dispatch->recv($repo, 1024);
        $res->{repo} = $repo;

        $log->_7("received repo: $repo");

        if ($repo){
            my $git = Test::BrewBuild::Git->new(debug => $self->{debug});

            $log->_7("before all checks, repo set to $repo");

            if (-d $git->name($repo)){
                chdir $git->name($repo) or croak $!;

                $log->_7("chdir to: ".getcwd());

                $log->_7("repo '".$git->name($repo)."' exists, pulling");
                $log->_7("using Git: " . $git->git);

                if (defined $self->{auto} && $self->{auto}){
                    $log->_6("in auto mode");

                    if (! defined $self->{csum}){
                        $log->_6("in auto mode, checking commit checksum reqs");

                        my $status = $git->status(repo => $git->link);
                        my $local_sum = $git->revision(repo => $git->link);
                        my $remote_sum = $git->revision(
                            remote => 1,
                            repo => $git->link
                        );

                        $log->_7(
                            "\nGit check:" .
                            "\n\tstatus: $status" .
                            "\n\tlocal: $local_sum" .
                            "\n\tremote: $remote_sum"
                        );

                        if (! $status) {
                            $log->_6(
                                "local repo is ahead in commits than remote... ".
                                "Nothing to do"
                            );
                            $self->{log} = '';
                            shutdown($dispatch, 1);
                            next;
                        }

                        if ($local_sum eq $remote_sum) {
                            $log->_6(
                                "local and remote commit sums match. Nothing to do"
                            );
                            $self->{log} = '';
                            shutdown($dispatch, 1);
                            next;
                        }
                    }
                }

                $log->_7("repo '".$git->name($repo)."' exists, pulling");
                $log->_7("using Git: " . $git->git);

                my $pull_output = $git->pull;
                $log->_7($pull_output);
            }
            else {
                $log->_7("repo doesn't exist... cloning");
                $git->clone($repo);
                chdir $git->name($repo);
                $log->_7("chdir to: ".getcwd());
            }

            my %opts = Test::BrewBuild->options(\@args);

            if (defined $opts{error}){
                my $err = "invalid arguments sent to brewbuild: ";
                $err .= join ', ', @args;
                $log->_0($err);
                $dispatch->send($err);
                next;
            }
            my $opt_str;

            for (keys %opts){
                $opt_str .= "$_ => $opts{$_}\n" if defined $opts{$_};
            }
            if ($opt_str){
                $log->_5("COMMENCING TEST RUN; args: $opt_str");
            }
            else {
                $log->_5("COMMENCING TEST RUN; no args (default)");
            }

            my $bb = Test::BrewBuild->new(%opts);

            $bb->log()->file($log_file) if ! $self->{log_to_stdout};

            $bb->instance_remove if $opts{remove};
            if ($opts{install}){
                $bb->instance_install($opts{install});
            }
            elsif ($opts{new}){
                $bb->instance_install($opts{new});
            }

            if ($opts{notest}){
                $log->_5("no tests run due to --notest flag set");
                $log->_5("storing and sending results back to dispatcher");
                $res->{log} = $self->{log};
                Storable::nstore_fd($res, $dispatch);
                next;
            }
            if ($opts{revdep}){
                $log->_6("revdep enabled");
                $res->{data} = $bb->revdep(%opts);
            }
            else {
                $log->_7("executing test()");
                $res->{data} = $bb->test;
            }

            if (-d 'bblog'){
                chdir 'bblog';
                $log->_7("chdir to: ".getcwd());
                my @entries = glob '*';
                $log->_5("log files: " . join ', ', @entries);
                for (@entries){
                    $log->_7("processing log file: " .getcwd() ."/$_");
                    next if ! -f || ! /\.bblog/;
                    open my $fh, '<', $_ or croak $!;
                    @{ $res->{files}{$_} } = <$fh>;
                    close $fh;
                }
                chdir '..';
                $log->_7("chdir to: ".getcwd());

                $log->_7("removing log dir: " . getcwd() . "/bblog");
                remove_tree 'bblog' or croak $!;
            }
            $log->_5("storing and sending results back to dispatcher");
            $res->{log} = $self->{log};

            Storable::nstore_fd($res, $dispatch);
            chdir '..';

            $self->{log} = '';
            shutdown($dispatch, 1);
        }
    }
    $sock->close();
}
sub ip {
    my ($self, $ip) = @_;

    return $self->{ip} if $self->{ip};

    if (! $ip && $self->{conf}{ip}){
        $ip = $self->{conf}{ip};
    }
    $ip = '0.0.0.0' if ! $ip;
    $self->{ip} = $ip;
}
sub port {
    my ($self, $port) = @_;

    return $self->{port} if $self->{port};

    if (! $port && $self->{conf}{port}){
        $port = $self->{conf}{port};
    }
    $port = '7800' if ! defined $port;
    $self->{port} = $port;
}
sub _config {
    # bring in config file elements

    my $self = shift;

    my $conf_file = Test::BrewBuild->config_file;

    if (-f $conf_file){
        my $conf = Config::Tiny->read($conf_file)->{tester};
        $self->{conf}{ip} = $conf->{ip};
        $self->{conf}{port} = $conf->{port};
    }
}
sub _pid_file {
    # fetch the PID file location
    my $self = shift;
    return $self->{pid_file} if defined $self->{pid_file};
    $self->{pid_file} = Test::BrewBuild->workdir . '/brewbuild.pid';
}
sub _unsafe_args {
    return ['*', '#', '!', '?', '^', '$', '|', '\\'];
}

1;

=head1 NAME

Test::BrewBuild::Tester - Daemonized testing service for dispatched test run
execution, for Windows & Unix.

=head1 DESCRIPTION

Builds and puts into the background a L<Test::BrewBuild> remote tester
listening service.

Note that by default, the working directory is C<~/brewbuild> on all platforms.

=head1 METHODS

=head2 new

Returns a new C<Test::BrewBuild::Tester> object.

Parameters:

    debug => $level

Integer, optional. Debug level from least verbose (0) to maximum verbosity (7).

    stdout => $bool

Integer, optional. By default, we return the test log/debug output with the
results of the test run. Set this to true (1) to disable this, and have the
tester print its output directly to STDOUT instead.

    logfile => $bool

Integer, optional. Set this to true (1) and we'll write all tester output to a
log file. The parent tester server will create a C<$workdir/bbtester_parent.log>
file (where C<$workdir> is C<~/brewbuild> by default), and the children tester
runners will all log to C<$workdir/bbtester_child.log>.

=head2 start

Starts the tester, and puts it into the background.

=head2 stop

Stops the tester and all of its processes.

=head2 status

Returns 1 if there's a tester currently running, and 0 if not.

=head2 ip($ip)

Default listening IP address is C<0.0.0.0> ie. all currently bound IPs. Send in
an alternate IP address to listen on a specific one.

This will override any IP information in the configuration file, if present.

Returns the currently used IP.

=head2 port($port)

Default port is C<7800>. Send in an alternate to listen on it instead.

This will override any port information in the configuration file, if present.

Returns the port currently being used.

=head2 listen

This is the actual service that listens for and processes requests.

By default, listens on all IP addresses bound to all network interfaces, on
port C<7800>.

=head1 AUTHOR

Steve Bertrand, C<< <steveb at cpan.org> >>

=head1 LICENSE AND COPYRIGHT

Copyright 2017 Steve Bertrand.

This program is free software; you can redistribute it and/or modify it
under the terms of either: the GNU General Public License as published
by the Free Software Foundation; or the Artistic License.

See L<http://dev.perl.org/licenses/> for more information.


=cut
 
