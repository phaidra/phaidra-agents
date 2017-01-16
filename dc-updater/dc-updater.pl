#!/usr/bin/env perl

=head1 NAME

dc-updater.pl


=head1 DESCRIPTION

Periodically checks MongoDB for updated objects and triggers dc update.

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

Log::Log4perl->easy_init( { level => $DEBUG, file => ">>/var/log/phaidra/dc-updater.log" } );

my $last_check = time;

while (defined (my $arg = shift (@ARGV)))
{
  $last_check = shift (@ARGV) if $arg eq '-since';  
}

#my $config = YAML::Syck::LoadFile('/etc/phaidra.yml');
my $config = from_json slurp('/usr/local/phaidra/phaidra-agents/phaidra-agents.json');

my $sleep = exists $config->{dcupdater}->{sleep} ? $config->{dcupdater}->{sleep} : 5;

my $mongouri;
if($config->{dcupdater}->{mongo_user}){
  $mongouri = "mongodb://".$config->{dcupdater}->{mongo_user}.":".$config->{dcupdater}->{mongo_password}."@". $config->{dcupdater}->{mongo_host}."/".$config->{dcupdater}->{mongo_db};
}else{
  $mongouri = "mongodb://". $config->{dcupdater}->{mongo_host}."/".$config->{dcupdater}->{mongo_db};
}
my $client = MongoDB->connect($mongouri);

=cut
my $client = MongoDB::MongoClient->new( "host" =>
"mongodb://$config->{'dcupdater'}->{'mongo_user'}:$config->{'dcupdater'}->{'mongo_password'}\@$config->{'dcupdater'}->{'mongo_host'}\/$config->{'dcupdater'}->{'mongo_db'}"
  );
=cut

=cut
my $client = MongoDB::Connection->new(
  host => $config->{dcupdater}->{mongo_host}, 
  port => "27017",
  username => $config->{dcupdater}->{mongo_user},
  password => $config->{dcupdater}->{mongo_password},
  db_name => $config->{dcupdater}->{mongo_db}
);
=cut

my $db = $client->get_database( $config->{'dcupdater'}->{'mongo_db'} );
my $col = $db->get_collection( $config->{'dcupdater'}->{'mongo_collection'} );

my $ua = Mojo::UserAgent->new;
my $apiurl = "https://".$config->{dcupdater}->{phaidraapi_adminusername}.":".$config->{dcupdater}->{phaidraapi_adminpassword}."\@".$config->{dcupdater}->{phaidraapi_apibaseurl};

my $cnt = 0;
while (1) {

    DEBUG("checking since $last_check [".(localtime $last_check)."]");
    
    # in case the find will take too long, take the timestemp before
    my $ts = time;
    my $updated = $col->find({'e' => { '$gte' => $last_check }}, { 'batchSize' => 100 })->sort({'e' => 1});
    $last_check = $ts;

    if($updated->has_next){

      while (my @b = $updated->batch) {

        # Remove duplicate pids
        my %do_pids;
        for my $d (@b){          
          if (
            ($d->{event} eq 'modifyDatastreamByValue' || $d->{event} eq 'addDatastream' ) 
            && (($d->{ds} eq 'UWMETADATA') || ($d->{ds} eq 'GEO'))
          ){
            $do_pids{$d->{pid}} = 1;
          }          
        }

        for my $d (keys %do_pids){     
          DEBUG("updating pid[$d]");
          my $tx = $ua->post( "$apiurl/object/$d/dc" );

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

