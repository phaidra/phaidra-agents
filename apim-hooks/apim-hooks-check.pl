#!/usr/bin/env perl
#
# Very basic process check. Put to crontab.
# eg */5 * * * * . $HOME/.bash_profile; cd /usr/local/phaidra/phaidra-agents/apim-hooks/ && ./apim-hooks-check.pl
#

use Mojo::File;
use Mojo::JSON 'from_json';
use MIME::Lite;
use Sys::Hostname;

my $configfilepath = Mojo::File->new('/usr/local/phaidra/phaidra-agents/phaidra-agents.json');
my $config = from_json $configfilepath->slurp;

my ($phaidraapi_baseurl, $monitoring)= map { $config->{apimhooks}->{$_} } qw(phaidraapi_baseurl monitoring);
my ($pidfile, $emailfrom, $emailto)= map { $monitoring->{$_} } qw(pidfile emailfrom emailto);

# print "url=[$phaidraapi_baseurl] emailfrom=[$emailfrom] emailto=[$emailto]\n";

my $alive = undef;
my $pid;
if(-r $pidfile){

  my $path = Mojo::File->new($pidfile);
  $pid = $path->slurp;

  $alive = (kill 0 => $pid);
}

my $host = hostname;

unless($alive){

    my $pwd = `pwd`; chop($pwd);
    my $msg = MIME::Lite->new(
	  From     => $emailfrom,
	  To       => $emailto,	  
	  Type     => 'text/html',
	  Subject  => "host[$host] pid[$pid] apim-hooks not running",
	  Data     => "Phaidra API-M hooks not running for $phaidraapi_baseurl; please go to $pwd and restart!"
    );

    $msg->send; 
}

1;
