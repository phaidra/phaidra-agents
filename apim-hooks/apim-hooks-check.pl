#!/usr/bin/env perl
#
# Very basic process check. Put to crontab.
# eg */5 * * * * . $HOME/.bash_profile; cd /usr/local/phaidra/phaidra-agents/apim-hooks/ && ./apim-hooks-check.pl
#

use Mojo::File;
use Mojo::JSON 'from_json';
use MIME::Lite;

my $configfilepath = Mojo::File->new('/usr/local/phaidra/phaidra-agents/phaidra-agents.json');
my $config = from_json $configfilepath->slurp;

my $pidfile = $config->{'apimhooks'}->{'monitoring'}->{pidfile};
my $emailfrom = $config->{'apimhooks'}->{'monitoring'}->{emailfrom};
my $emailto = $config->{'apimhooks'}->{'monitoring'}->{emailto};

my $alive = undef;
my $pid;
if(-r $pidfile){

  my $path = Mojo::File->new($pidfile);
  $pid = $path->slurp;

  $alive = (kill 0 => $pid);
}

if($alive){

  print "[$pid] running\n";

}else{

  print "[$pid] not running\n";

    my $msg = MIME::Lite->new(
	  From     => $emailfrom,
	  To       => $emailto,	  
	  Type     => 'text/html',
	  Subject  => "[$pid] apim-hooks not running",
	  Data     => ""
    );

    $msg->send; 
}

1;
