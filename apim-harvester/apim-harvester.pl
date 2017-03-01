#!/usr/bin/env perl

=head1 NAME

apim-harvester.pl


=head1 DESCRIPTION

This is glue code that takes data from activemq [Apache messaging bus]
and writes it to MongoDB Because of the current limitation in fedora-commons, 
it only has api-m records at the moment.

=cut

use Net::Stomp;
use XML::XML2JSON;
use JSON::XS;
use Mojo::JSON 'from_json';
use Mojo::Util 'slurp';
use MongoDB;
use Data::Dumper;
use Log::Log4perl qw(:easy);

Log::Log4perl->easy_init( { level => $DEBUG, file => ">>/var/log/phaidra/apim-harvester.log" } );

my $config = from_json slurp('/usr/local/phaidra/phaidra-agents/phaidra-agents.json');

# format is: my $client = MongoDB::MongoClient->new( "host" =>
#      "mongodb://username:pass\@host\/db" );
# one in the doc, doesn't seem to work?

my $uri = "mongodb://".$config->{apimharvester}->{mongo_user}.":".$config->{apimharvester}->{mongo_password}."@". $config->{apimharvester}->{mongo_host}."/".$config->{apimharvester}->{mongo_db};
my $client = MongoDB->connect($uri);

=cut
my $client = MongoDB::MongoClient->new( "host" =>
"mongodb://$config->{'apimharvester'}->{'mongo_user'}:$config->{'apimharvester'}->{'mongo_password'}\@$config->{'apimharvester'}->{'mongo_host'}\/$config->{'apimharvester'}->{'mongo_db'}"
  );
=cut

=cut
my $client = MongoDB::Connection->new(
  host => $config->{apimharvester}->{mongo_host}, 
  port => "27017",
  username => $config->{apimharvester}->{mongo_user},
  password => $config->{apimharvester}->{mongo_password},
  db_name => $config->{apimharvester}->{mongo_db}
);
=cut

my $db = $client->get_database( $config->{'apimharvester'}->{'mongo_db'} );
my $messages = $db->get_collection( $config->{'apimharvester'}->{'mongo_collection'} );

# store the frame bodies here for debugging before trying to put into Mongo
#my $debug_file = 'debug.txt';
#open my $fh, '>>', $debug_file;

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
while (1) {

    my $frame = $stomp->receive_frame;

    my $converter = XML::XML2JSON->new( 'force_array' => 1 );
    my $json = $converter->convert( $frame->body );
    my $decoded = JSON::XS::decode_json($json);    
    #$log->debug( $frame->body );

    my $pid = $decoded->{entry}->{summary}[0]->{'$t'};
    my $event = $decoded->{entry}->{title}[0]->{'$t'};
    my $ds;
    my $catsize = scalar @{$decoded->{entry}->{category}};
    if($catsize > 2){
      if($decoded->{entry}->{category}[1]->{'@scheme'} eq 'fedora-types:dsID'){
        $ds = $decoded->{entry}->{category}[1]->{'@term'};
      }
    }
    my $e = time;
    my $message = { 
      'data' => $decoded, 
      'e' => $e, 
      'pid' => $pid, 
      'event' => $event      
    };
    my $str = "pid[$pid] event[$event] e[$e]";
    if($ds){
      $message->{ds} = $ds;
      $str .= " ds[$ds]";
    }
    DEBUG("saving $str");
    my $id = $messages->insert_one($message);

    INFO("saved $str id[$id]");
    $stomp->ack( { frame => $frame } );

}

$stomp->disconnect;
exit 0;

