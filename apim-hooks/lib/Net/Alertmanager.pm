#!/usr/bin/perl

package Net::Alertmanager;

use JSON;
use LWP::UserAgent;
use Data::Dumper;

sub new
{
  my $class= shift;
  my $self=
  {
    # alertmanager => { url => 'http://localhost:9095/', ... }
  };
  bless $self, $class;
  $self->set(@_);

  $self;
}

sub set
{
  my $self= shift;
  my %par= @_;
  foreach my $par (keys %par)
  {
    $self->{$par}= $par{$par};
  }
  $self;
}

sub send_alerts
{
  my $self= shift;
  my $alerts= shift;

  my $json= JSON::encode_json($alerts);
  # print __FILE__, " ", __LINE__, " json=[$json]\n";

  my $a= $self->{alertmanager};
  unless ($a)
  {
    print STDERR " can't access alertmanager config!\n";
    return ('MISSING_CONFIG', undef);
  }

  my $req= new HTTP::Request(POST => $a->{url});
  $req->authorization_basic($a->{username}, $a->{password});
  $req->content_type('application/json');
  $req->content($json);

  my $ua=  new LWP::UserAgent;
  my $res= $ua->request($req);

  my ($msg, $content, $data);
  if ($res->is_success)
  {
    $msg= 'OK';
    $content= $res->content;
    $data= JSON::decode_json($content);
    # print __LINE__, " data: ", Dumper($data);
  }
  else
  {
    # print __LINE__, " res: ", Dumper($res), "\n";
    $msg= $res->status_line;
  }

  # print __LINE__, " msg=[$msg]\n"; # content=[$content]\n";
  ($data, $msg);
}

sub read_config
{
  my $fnm= shift;
  open(FI, '<:utf8', $fnm) or die "can't read $fnm";
  my @text= <FI>;
  my $text= join('', @text);
  # print __LINE__, " text=[$text]\n";
  close(FI);
  JSON::decode_json($text);
}

1;

