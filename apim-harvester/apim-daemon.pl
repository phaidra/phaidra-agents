#!/usr/bin/perl
use warnings;
use strict;
use Daemon::Control;
 
exit Daemon::Control->new(
    name        => "ActiveMQ Message Logger",
    lsb_start   => '$syslog $remote_fs',
    lsb_stop    => '$syslog',
    lsb_sdesc   => 'Message Logger',
    lsb_desc    => 'Takes api-m messages and logs them to mongo.',
    path        => '/etc/init.d/apim-harvester',
 
    program     => '/root/perl/apim-harvester.pl',
  #  program_args => [ '--debug' ], for debugging the harvester
 
    pid_file    => '/tmp/apim-harvester.pid',
    stderr_file => '/tmp/apim-harvester.out',
    stdout_file => '/tmp/apim-harvester.out',
 
    fork        => 2,
 
)->run;
