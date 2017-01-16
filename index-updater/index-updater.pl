#!/usr/bin/env perl

=head1 NAME

index-updater.pl


=head1 DESCRIPTION

Periodically checks MongoDB for updated index entries and sends them to index.

=cut

use Net::Stomp;
use XML::XML2JSON;
use JSON::XS;
use YAML::Syck;
use MongoDB;
use Mojo::UserAgent;
use Mojo::JSON 'from_json';
use Mojo::Util 'slurp';
use Log::Log4perl qw(:easy);
use Data::Dumper;

Log::Log4perl->easy_init( { level => $DEBUG, file => ">>/var/log/phaidra/index-updater.log" } );

my $last_check = time;

while (defined (my $arg = shift (@ARGV)))
{
  $last_check = shift (@ARGV) if $arg eq '-since';  
}

#my $config = YAML::Syck::LoadFile('/etc/phaidra.yml');
my $config = from_json slurp('/usr/local/phaidra/phaidra-agents/phaidra-agents.json');

my $sleep = exists $config->{indexupdater}->{sleep} ? $config->{indexupdater}->{sleep} : 5;

my $mongouri;
if($config->{indexupdater}->{mongo_user}){
  $mongouri = "mongodb://".$config->{indexupdater}->{mongo_user}.":".$config->{indexupdater}->{mongo_password}."@". $config->{indexupdater}->{mongo_host}."/".$config->{indexupdater}->{mongo_db};
}else{
  $mongouri = "mongodb://". $config->{indexupdater}->{mongo_host}."/".$config->{indexupdater}->{mongo_db};
}
my $client = MongoDB->connect($mongouri);

=cut
my $client = MongoDB::MongoClient->new( "host" =>
"mongodb://$config->{'indexupdater'}->{'mongo_user'}:$config->{'indexupdater'}->{'mongo_password'}\@$config->{'indexupdater'}->{'mongo_host'}\/$config->{'indexupdater'}->{'mongo_db'}"
  );
=cut

=cut
my $client = MongoDB::Connection->new(
  host => $config->{indexupdater}->{mongo_host}, 
  port => "27017",
  username => $config->{indexupdater}->{mongo_user},
  password => $config->{indexupdater}->{mongo_password},
  db_name => $config->{indexupdater}->{mongo_db}
);
=cut

my $db = $client->get_database( $config->{'indexupdater'}->{'mongo_db'} );
my $col = $db->get_collection( $config->{'indexupdater'}->{'mongo_collection'} );

my $ua = Mojo::UserAgent->new;
my $apiurl = "https://".$config->{indexupdater}->{phaidraapi_adminusername}.":".$config->{indexupdater}->{phaidraapi_adminpassword}."\@".$config->{indexupdater}->{phaidraapi_apibaseurl};

my $cnt = 0;
while (1) {

    DEBUG("checking since $last_check [".(localtime $last_check)."]");
    
    # in case the find will take too long, take the timestemp before
    my $ts = time;
    my $updated = $col->find({'e' => { '$gte' => $last_check }}, { 'batchSize' => 100 })->sort({'e' => 1});
    $last_check = $ts;

    if($updated->has_next){

      while (my @b = $updated->batch) {

        # Only update on DC_P. We'll act as if DC_P is updated iif something interesting happens to the object
        my %do_pids;
        for my $d (@b){          
          if (
            ($d->{event} eq 'modifyDatastreamByValue' || $d->{event} eq 'addDatastream' ) 
            && (($d->{ds} eq 'DC_P'))
          ){
            $do_pids{$d->{pid}} = 1;
          }          
        }

        for my $d (keys %do_pids){     
          INFO("updating pid[$d]");
          my $tx = $ua->post( "$apiurl/object/$d/index" );

          if (my $res = $tx->success) {
            INFO("updated pid[$d]");
          }else {
            my ($err, $code) = $tx->error;
            ERROR("updating pid[$d] failed ".Dumper($err));
          }
        }

      }

    }else{
      sleep($sleep);
    }

}

exit 0;

