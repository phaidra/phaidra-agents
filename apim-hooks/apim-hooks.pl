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
use Mojo::Util 'slurp';
use Data::Dumper;
use Log::Log4perl qw(:easy);

Log::Log4perl->easy_init( { level => $DEBUG, file => ">>/var/log/phaidra/apim-hooks.log" } );

my $config = from_json slurp('/usr/local/phaidra/phaidra-agents/phaidra-agents.json');

my $ua = Mojo::UserAgent->new;
my $apiurl = "https://".$config->{apimhooks}->{phaidraapi_adminusername}.":".$config->{apimhooks}->{phaidraapi_adminpassword}."\@".$config->{apimhooks}->{phaidraapi_apibaseurl};
my $solrurl = $config->{apimhooks}->{solr_scheme}."://".$config->{apimhooks}->{solr_host}.":".$config->{apimhooks}->{solr_port}."/solr/".$config->{apimhooks}->{solr_core}."/update/json/docs?commit=true";

# set up connection to activemq on default port for non-ssl stomp
my $stomp = Net::Stomp->new(
    {
        hostname => $config->{'apimharvester'}->{'stomp_host'},
        port     => $config->{'apimharvester'}->{'stomp_port'}
    }
);
$stomp->connect();

# this will create the topics, as described in: https://wiki.duraspace.org/display/FEDORA34/Messaging
# if they are not already created

my $return_code;
$return_code = $stomp->subscribe(
    {
        'destination' => "/topic/$config->{'apimharvester'}->{'update_topic'}",
        'ack'         => 'client',
    }
);
$return_code = $stomp->subscribe(
    {
        'destination' => "/topic/$config->{'apimharvester'}->{'access_topic'}",
        'ack'         => 'client',
    }
);

# receive frame, will block until there is a frame
INFO("started");
my $tx;
while (1) {

  my $frame = $stomp->receive_frame;

  my $converter = XML::XML2JSON->new( 'force_array' => 1 );
  my $json = $converter->convert( $frame->body );
  my $decoded = JSON::XS::decode_json($json);    

  my $pid = $decoded->{entry}->{summary}[0]->{'$t'};
  my $event = $decoded->{entry}->{title}[0]->{'$t'};
  my $ds;
  my $catsize = scalar @{$decoded->{entry}->{category}};
  if($catsize > 2){
    if($decoded->{entry}->{category}[1]->{'@scheme'} eq 'fedora-types:dsID'){
      $ds = $decoded->{entry}->{category}[1]->{'@term'};
    }
  }
=cut
  if((($event eq 'modifyDatastreamByValue') || ($event eq 'addDatastream')) && ($ds eq 'RELS-EXT')){
    
    DEBUG("catching pid[$pid] event[$event] e[".time."] ds[$ds]");

    if($res->json->{result}->{index}->{cmodel} eq 'Collection'){

      $tx = $ua->post("$apiurl/object/$pid/index");
      if (my $res = $tx->success) {

        INFO("index updated pid[$pid]");
        
        my $index = $res->json->{result}->{index};
        my $members = $index->{haspart};
       
        my $tx = $ua->post( $solrurl => json => $index );  
        if (my $res = $tx->success) {
          INFO("solr updated pid[$pid]");
        }else {
          ERROR("updating solr pid[$pid] failed ".Dumper($tx->error));              
        }  

        INFO("members");
        my $cnt = $members;
        my $i = 0;
        for my $m (@{$members}){
          $i++;

          my $update = (
            pid => $m,
            ispartof => { add => $pid }
          );

          my $tx = $ua->post( $solrurl => json => $update );  
          if (my $res = $tx->success) {
            INFO("[$i/$cnt] member index updated pid[$m]");
          }else {
            ERROR("[$i/$cnt] updating member index pid[$m] failed ".Dumper($tx->error));              
          }
          
        }
          
      }

    }else {
      ERROR("updating index pid[$pid] failed ".Dumper($tx->error));
    }
  }
=cut
  if((($event eq 'modifyDatastreamByValue') || ($event eq 'addDatastream')) && (($ds eq 'UWMETADATA') || ($ds eq 'MODS'))){
    
    DEBUG("catching pid[$pid] event[$event] e[".time."] ds[$ds]");

    $tx = $ua->post("$apiurl/object/$pid/dc");
    if (my $res = $tx->success) {
      INFO("dc updated pid[$pid]");
    }else {
      ERROR("updating dc pid[$pid] failed ".Dumper($tx->error));
    }

    $tx = $ua->post("$apiurl/object/$pid/index");
    if (my $res = $tx->success) {

      INFO("index updated pid[$pid]");

      my $index = $res->json->{result}->{index};

      if($res->json->{result}->{index}->{cmodel} ne 'Page'){

        my $tx = $ua->post( $solrurl => json => $index );  
        if (my $res = $tx->success) {
          INFO("solr updated pid[$pid]");
        }else {
          ERROR("updating solr pid[$pid] failed ".Dumper($tx->error));              
        }  

      }else{
        DEBUG("skipping solr update for Page pid[$pid]");
      }

    }else {
      ERROR("updating index pid[$pid] failed ".Dumper($tx->error));
    }

  }

  $stomp->ack( { frame => $frame } );

}

$stomp->disconnect;
exit 0;

