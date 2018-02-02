#!/usr/bin/env perl
use warnings;
use strict;
use Mojo::JSON 'from_json';
use Mojo::File;
use Daemon::Control;
 
my $configfilepath = Mojo::File->new('/usr/local/phaidra/phaidra-agents/phaidra-agents.json');
my $config = from_json $configfilepath->slurp;

my $pidfile = $config->{'apimhooks'}->{'monitoring'}->{pidfile};

exit Daemon::Control->new(
    name        => "apim-hooks daemon",
    lsb_start   => '$syslog $remote_fs',
    lsb_stop    => '$syslog',
    lsb_sdesc   => 'Phaidra agent',
    lsb_desc    => 'Listens for apim events and 1) updates DC 2) updates mongo index 3) updates solr index.',
    path        => '/usr/local/phaidra/phaidra-agents/apim-hooks',
    program     => '/usr/local/phaidra/phaidra-agents/apim-hooks/apim-hooks.pl',
    pid_file    => $pidfile,
    stderr_file => '/var/log/phaidra/apim-hooks-daemon.log',
    stdout_file => '/var/log/phaidra/apim-hooks-daemon.log',
    fork        => 2,
)->run;
