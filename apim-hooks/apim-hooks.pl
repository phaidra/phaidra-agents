#!/usr/bin/env perl

=head1 NAME

apim-hooks.pl

=head1 DESCRIPTION

Listens for apim events and 1) creates image server job if enabled 2) creates handle identifier if enabled 3) updates solr index.

=cut

use Net::Stomp;
use XML::XML2JSON;
use JSON::XS;
use Mojo::UserAgent;
use Mojo::JSON 'from_json';
use Mojo::File;
use Data::Dumper;
use Log::Log4perl qw(:easy);
use MongoDB 1.8.3;

Log::Log4perl->easy_init( { level => $DEBUG, layout => "[%d] [%c] [%p] %m%n", file => ">>/var/log/phaidra/apim-hooks.log" } );

sub ts_iso {
  my @ts = localtime (time());
  sprintf ("%04d%02d%02dT%02d%02d%02d", $ts[5]+1900, $ts[4]+1, $ts[3], $ts[2], $ts[1], $ts[0]);
}

sub insert_handle {
  my $irma_coll = shift;
  my $hdl = shift;
  my $url = shift;

  INFO("inserting url=[$url] hdl=[$hdl]");
  $irma_coll->insert_one(
    {
      ts_iso => ts_iso(),
      _created => time,
      _updated => time,
      hdl => $hdl,
      url => $url
    }
  );
}

my $configfilepath = Mojo::File->new('/usr/local/phaidra/phaidra-agents/phaidra-agents.json');
my $config = from_json $configfilepath->slurp;

my $irma_coll;
if (exists($config->{apimhooks}->{irma_mongo})){
  my $mdbcfg= $config->{apimhooks}->{irma_mongo};
  my %connection_pars= map { $_ => $mdbcfg->{$_} } qw(host port username password database);
  my $irma_mongo;
  eval { $irma_mongo = new MongoDB::MongoClient (%connection_pars); };
  if ($@) {
    ERROR("error connecting to mongo: ".$@);
    exit 1;
  }
  my $irma_db = $irma_mongo->get_database($mdbcfg->{database});
  $irma_coll = $irma_db->get_collection('irma.map');
}

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
while (1) {

  my $frame = $stomp->receive_frame;

  my $converter = XML::XML2JSON->new( 'force_array' => 1, 'module' => 'JSON::XS' );
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

  if(($event eq 'modifyObject') || (($event eq 'modifyDatastreamByValue') && (($ds eq 'UWMETADATA') || ($ds eq 'MODS') || ($ds eq 'RIGHTS') || ($ds eq 'JSON-LD') || ($ds eq 'COLLECTIONORDER'))) || (($event eq 'addDatastream') && (($ds eq 'RIGHTS') || ($ds eq 'COLLECTIONORDER')))){

    DEBUG("catching pid[$pid] event[$event] e[".time."] ds[$ds] state[$state]");

    if(($event eq 'modifyObject') && ($state eq 'A')){
      # DEBUG(Dumper($decoded));

      my $cmodel;
      my $cmres = $ua->get("$apiurl/object/$pid/cmodel")->result;
      if ($cmres->is_success) {
        $cmodel = $cmres->json->{cmodel};
        INFO("pid[$pid] cmodel[".$cmodel."]");
      }else {
        ERROR("getting cmodel of pid[$pid] ".$cmres->code." ".$cmres->message);
      }

      if(exists($config->{apimhooks}->{create_imageserver_job}) && $config->{apimhooks}->{create_imageserver_job} eq 1){
        # if Picture or PDF, create imageserver job
        if($cmodel && ($cmodel eq 'Picture') || ($cmodel eq 'PDFDocument')){
          my $procres = $ua->post("$apiurl/imageserver/$pid/process")->result;
          if ($procres->is_success) {
            INFO("imageserver job created pid[$pid]");
          }else {
            ERROR("creating imageserver job for pid[$pid] failed ".$procres->code." ".$procres->message);
          }
        }
      }

      if (exists($config->{apimhooks}->{handle}) && ($config->{apimhooks}->{handle}->{create_handle} eq 1) && exists($config->{apimhooks}->{irma_mongo}) && $irma_coll) {
        # create handle
        my ($pidnoprefix) = $pid =~ /o:(\d+)/;
        my $hdl = $config->{apimhooks}->{handle}->{hdl_prefix}."/".$config->{apimhooks}->{handle}->{instance_hdl_prefix}.".".$pidnoprefix;
        my $url = $config->{apimhooks}->{handle}->{instance_url_prefix}.$pid;

        my $found = $irma_coll->find_one({hdl => $hdl, url => $url});
        if (defined($found) && exists($found->{hdl})) {
          INFO("skipping, ".$found->{hdl}." already in irma.map"); 
        } else { 
          my $ignore_pages = '1';
          if(exists($config->{apimhooks}->{handle}->{ignore_pages})) {
            $ignore_pages = $config->{apimhooks}->{handle}->{ignore_pages};
          }
          if ($ignore_pages eq '0') {
            insert_handle($irma_coll, $hdl, $url);
          } else {
            # if not Page object, insert handle identifier
            if ($cmodel && ($cmodel ne 'Page')) {
              insert_handle($irma_coll, $hdl, $url);
            }
          }
        }
      }
    }

    my $idxres = $ua->post("$apiurl/object/$pid/index")->result;
    if ($idxres->is_success) {
      INFO("index updated pid[$pid]");
    }else {
      ERROR("updating index pid[$pid] failed ".$idxres->code." ".$idxres->message);
    }
  }  

  $stomp->ack( { frame => $frame } );

}

$stomp->disconnect;
exit 0;
