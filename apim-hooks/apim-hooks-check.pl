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

use lib '/usr/share/perl5';
use lib '/usr/share/perl5/vendor_perl';
use lib 'lib';
use Net::Alertmanager;

my ($phaidraapi_baseurl, $monitoring)= map { $config->{apimhooks}->{$_} } qw(phaidraapi_baseurl monitoring);
my ($pidfile, $emailfrom, $emailto, $enableemail, $enablealert, $instance)= map { $monitoring->{$_} } qw(pidfile emailfrom emailto enableemail enablealert instance);

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

  if ($enableemail) # or option to send mail activated
  {
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

  if ($enablealert) # or option to send alerts via alertmanager activated
  {
    my $acfg= (exists ($config->{alertmanager}))
               ? $config->{alertmanager}   # where the config should be, logically
	       : $config->{apimhooks}->{alertmanager}; # where the config is apparently
    my $alertmanager= new Net::Alertmanager (alertmanager => $acfg);

    my $alert=
    {
      labels =>
      {
        # required?
        severity => 'page',
        instance => 'apim-hooks-'.$instance,
        alertname => 'apim-hooks-down',
	host => $host,
	phaidraapi_baseurl => $phaidraapi_baseurl,

        # univie
        # alert => 'gg', # who should receive the alert; if not present, defaults will apply
      },
      annotations =>
      {
        description => 'apim-hooks not running',
        summary => 'apim-hooks not running',
      },
      # startsAt => "",
      # endsAt => "",
      # generatorURL => "",
    };

    $alertmanager->send_alerts( [ $alert ] );
  }
}

1;
