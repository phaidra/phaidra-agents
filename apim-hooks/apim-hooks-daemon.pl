#!/usr/bin/env perl
use warnings;
use strict;
use Daemon::Control;
 
exit Daemon::Control->new(
    name        => "ActiveMQ Message Logger",
    lsb_start   => '$syslog $remote_fs',
    lsb_stop    => '$syslog',
    lsb_sdesc   => 'Phaidra agent',
    lsb_desc    => 'Listens for apim events and 1) updates DC 2) updates mongo index 3) updates solr index.',
    path        => '/usr/local/phaidra/phaidra-agents/apim-hooks',
    program     => '/usr/local/phaidra/phaidra-agents/apim-hooks/apim-hooks.pl',
    pid_file    => '/usr/local/phaidra/phaidra-agents/apim-hooks/apim-hooks.pid',
    stderr_file => '/var/log/phaidra/apim-hooks-daemon.log',
    stdout_file => '/var/log/phaidra/apim-hooks-daemon.log',
    fork        => 2,
)->run;
