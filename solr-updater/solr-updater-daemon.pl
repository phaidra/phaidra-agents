#!/usr/bin/env perl

=pod
=head1 solr-updater-daemon.pl (-since sinceepoch)
  -since sinceepoch - check index database for updates since this date
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
    name        => "Solr index updater",
    lsb_start   => '$syslog $remote_fs',
    lsb_stop    => '$syslog',
    lsb_sdesc   => 'Phaidra agent: solr index updater',
    lsb_desc    => 'Takes new index entries from MongoDB and sends them to Solr.',
    path        => '/usr/local/phaidra/phaidra-agents/solr-updater',
    program     => '/usr/local/phaidra/phaidra-agents/solr-updater/solr-updater.pl',
    pid_file    => '/usr/local/phaidra/phaidra-agents/solr-updater/solr-updater.pid',
    stderr_file => '/var/log/phaidra/solr-updater-daemon.log',
    stdout_file => '/var/log/phaidra/solr-updater-daemon.log', 
    fork        => 2, 
);

$daemon->program_args( [ '-since', $since ] ) if defined $since;

exit $daemon->run;
