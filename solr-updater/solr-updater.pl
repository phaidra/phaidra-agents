#!/usr/bin/env perl

=head1 NAME

solr-updater.pl


=head1 DESCRIPTION

Periodically checks MongoDB for updated index entries and sends them to Solr.

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

Log::Log4perl->easy_init( { level => $DEBUG, file => ">>/var/log/phaidra/solr-updater.log" } );

my $last_check = time;

while (defined (my $arg = shift (@ARGV)))
{
  $last_check = shift (@ARGV) if $arg eq '-since';  
}

#my $config = YAML::Syck::LoadFile('/etc/phaidra.yml');
my $config = from_json slurp('/usr/local/phaidra/phaidra-agents/phaidra-agents.json');

my $sleep = exists $config->{solrupdater}->{sleep} ? $config->{solrupdater}->{sleep} : 5;

my $mongouri;
if($config->{solrupdater}->{mongo_user}){
  $mongouri = "mongodb://".$config->{solrupdater}->{mongo_user}.":".$config->{solrupdater}->{mongo_password}."@". $config->{solrupdater}->{mongo_host}."/".$config->{solrupdater}->{mongo_db};
}else{
  $mongouri = "mongodb://". $config->{solrupdater}->{mongo_host}."/".$config->{solrupdater}->{mongo_db};
}
my $client = MongoDB->connect($mongouri);

=cut
my $client = MongoDB::MongoClient->new( "host" =>
"mongodb://$config->{'solrupdater'}->{'mongo_user'}:$config->{'solrupdater'}->{'mongo_password'}\@$config->{'solrupdater'}->{'mongo_host'}\/$config->{'solrupdater'}->{'mongo_db'}"
  );
=cut

=cut
my $client = MongoDB::Connection->new(
  host => $config->{solrupdater}->{mongo_host}, 
  port => "27017",
  username => $config->{solrupdater}->{mongo_user},
  password => $config->{solrupdater}->{mongo_password},
  db_name => $config->{solrupdater}->{mongo_db}
);
=cut

my $db = $client->get_database( $config->{'solrupdater'}->{'mongo_db'} );
my $col = $db->get_collection( $config->{'solrupdater'}->{'mongo_collection'} );

my $ua = Mojo::UserAgent->new;
my $solrurl = $config->{solrupdater}->{solr_scheme}."://".$config->{solrupdater}->{solr_host}.":".$config->{solrupdater}->{solr_port}."/solr/".$config->{solrupdater}->{solr_core}."/update/json/docs?commit=true";

my $cnt = 0;
while (1) {

    DEBUG("checking since $last_check [".(localtime $last_check)."]");
    
    # in case the find will take too long, take the timestemp before
    my $ts = time;
    my $updated = $col->find({'_updated' => { '$gte' => $last_check }}, { 'batchSize' => 100 });    
    $last_check = $ts;

    if($updated->has_next){    

      while (my @b = $updated->batch) {          
        
        my @pids;
        for my $d (@b){
          $d->{_id} = scalar $d->{_id};
          push @pids, $d->{pid};
        }

        DEBUG("updating ".(0+@b)." docs\n".Dumper(\@pids));

        # send bulk update to solr
        my $tx = $ua->post( $solrurl => json => \@b );  

        if (my $res = $tx->success) {
          INFO("updated\n".Dumper(\@pids));
        }else {
          my ($err, $code) = $tx->error;
          ERROR("updating\n".Dumper(\@pids)."\nfailed ".Dumper($err));              
        }         
      }

    }else{
      sleep($sleep);
    }
    

}

exit 0;

