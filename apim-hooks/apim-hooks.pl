#!/usr/bin/env perl

=head1 NAME

apim-hooks.pl

=head1 DESCRIPTION

Listens for apim events and 1) updates DC 2) updates mongo index 3) updates solr index.

=cut

use Net::Stomp;
use XML::XML2JSON;
use JSON::XS;
use Mojo::UserAgent;
use Mojo::JSON 'from_json';
use Mojo::File;
use Data::Dumper;
use Log::Log4perl qw(:easy);

Log::Log4perl->easy_init( { level => $DEBUG, layout => "[%d] [%c] [%p] %m%n", file => ">>/var/log/phaidra/apim-hooks.log" } );

my $configfilepath = Mojo::File->new('/usr/local/phaidra/phaidra-agents/phaidra-agents.json');
my $config = from_json $configfilepath->slurp;

my $ua = Mojo::UserAgent->new;
my $apiurl = "https://".$config->{apimhooks}->{phaidraapi_adminusername}.":".$config->{apimhooks}->{phaidraapi_adminpassword}."\@".$config->{apimhooks}->{phaidraapi_baseurl};

# set up connection to activemq on default port for non-ssl stomp
my $stomp = Net::Stomp->new(
    {
        hostname => $config->{'apimhooks'}->{'stomp_host'},
        port     => $config->{'apimhooks'}->{'stomp_port'}
    }
);
$stomp->connect();

# this will create the topics, as described in: https://wiki.duraspace.org/display/FEDORA34/Messaging
# if they are not already created

my $return_code;
$return_code = $stomp->subscribe(
    {
        'destination' => "/topic/$config->{'apimhooks'}->{'update_topic'}",
        'ack'         => 'client',
    }
);
$return_code = $stomp->subscribe(
    {
        'destination' => "/topic/$config->{'apimhooks'}->{'access_topic'}",
        'ack'         => 'client',
    }
);

# receive frame, will block until there is a frame
INFO("started");
my $tx;
while (1) {

  my $frame = $stomp->receive_frame;

  my $converter = XML::XML2JSON->new( 'force_array' => 1 );
  # this seems to be undefined sometimes
  unless($frame->body){
     ERROR("caught empty message");
     next;
  }
  my $json = $converter->convert( $frame->body );
  my $decoded = JSON::XS::decode_json($json);    

  my $pid = $decoded->{entry}->{summary}[0]->{'$t'};
  my $event = $decoded->{entry}->{title}[0]->{'$t'};
  my $ds;
  my $state;
  my $catsize = scalar @{$decoded->{entry}->{category}};
  if($catsize > 2){
    if($decoded->{entry}->{category}[1]->{'@scheme'} eq 'fedora-types:dsID'){
      $ds = $decoded->{entry}->{category}[1]->{'@term'};
    }
    if($decoded->{entry}->{category}[1]->{'@scheme'} eq 'fedora-types:state'){
      $state = $decoded->{entry}->{category}[1]->{'@term'};
    }
  }

  if(($event eq 'modifyObject') || (($event eq 'modifyDatastreamByValue') && (($ds eq 'UWMETADATA') || ($ds eq 'MODS') || ($ds eq 'RIGHTS'))) || (($event eq 'addDatastream') && ($ds eq 'RIGHTS'))){
    
    if(exists($config->{apimhooks}->{create_imageserver_job}) && $config->{apimhooks}->{create_imageserver_job} eq 1){
      if(($event eq 'modifyObject') && ($state eq 'A')){
        # DEBUG(Dumper($decoded));
        $tx = $ua->get("$apiurl/object/$pid/cmodel");
        if (my $res = $tx->success) {
          if($res->json->{cmodel} eq 'Picture'){
            $tx = $ua->post("$apiurl/imageserver/$pid/process");
            if (my $res = $tx->success) {
              INFO("imageserver job created pid[$pid]");
            }else {
              ERROR("creating imageserver job for pid[$pid] failed ".Dumper($tx->error));
            }
          }
        }else {
          ERROR("getting cmodel of pid[$pid] ".Dumper($tx->error));
        }
      }
    }

    DEBUG("catching pid[$pid] event[$event] e[".time."] ds[$ds] state[$state]");

    $tx = $ua->post("$apiurl/object/$pid/index");
    if (my $res = $tx->success) {
      INFO("index updated pid[$pid]");
    }else {
      ERROR("updating index pid[$pid] failed ".Dumper($tx->error));
    }

  }

  $stomp->ack( { frame => $frame } );

}

$stomp->disconnect;
exit 0;

