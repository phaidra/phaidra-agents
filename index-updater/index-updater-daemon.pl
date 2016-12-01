#!/usr/bin/env perl

=pod
=head1 index-updater-daemon.pl (-since sinceepoch)
  -since sinceepoch - check updates since this date
=cut

use warnings;
use strict;
use Daemon::Control;
use Data::Dumper;

my $since;
my @args = @ARGV;
while (defined (my $arg = shift (@args)))
{
  if ($arg =~ /^-/)
  {
       if ($arg eq '-since') { $since = shift (@args); }
    else { system ("perldoc '$0'"); exit (0); }
  }
}

my $daemon = Daemon::Control->new(
    name        => "Index updater",
    lsb_start   => '$syslog $remote_fs',
    lsb_stop    => '$syslog',
    lsb_sdesc   => 'Phaidra agent: index updater',
    lsb_desc    => 'Watches for updated objects and updates index collection for these.',
    path        => '/usr/local/phaidra/phaidra-agents/index-updater',
    program     => '/usr/local/phaidra/phaidra-agents/index-updater/index-updater.pl',
    pid_file    => '/usr/local/phaidra/phaidra-agents/index-updater/index-updater.pid',
    stderr_file => '/var/log/phaidra/index-updater-daemon.log',
    stdout_file => '/var/log/phaidra/index-updater-daemon.log', 
    fork        => 2, 
);

$daemon->program_args( [ '-since', $since ] ) if defined $since;

exit $daemon->run;
