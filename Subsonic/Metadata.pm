package Plugins::Subsonic::Metadata;

use strict;

use Slim::Formats::RemoteMetadata;
use Slim::Formats::XML;
use Slim::Music::Info;

use Slim::Utils::Log;
use Slim::Utils::Prefs;
use URI;
use Plugins::Subsonic::API;

my $prefs = preferences('plugin.subsonic');
my $log = logger('plugin.subsonic');

sub init {
	my $class = shift;
  my $baseurl = quotemeta($prefs->get('baseurl'));
	Slim::Formats::RemoteMetadata->registerProvider(
		match => qr/$baseurl/,
		func  => \&provider,
	);

  Slim::Formats::RemoteMetadata->registerParser(
    match => qr/$baseurl/,
    func  => \&parser,
  );
}

sub provider {
	my ( $client, $url ) = @_;
  my $uri = URI->new($url);
  my %query = $uri->query_form;
  Plugins::Subsonic::API->gettrackInfo(sub { _infoCallback(shift); }, $query{'id'});
}

sub _infoCallback {
	my $info = shift;
  #$log->debug(Data::Dump::dump($info));
  my $image = Plugins::Subsonic::API->getcoverArt($info->{'subsonic-response'}->{'song'}->{'coverArt'}) || 'html/images/playlists.png';
  #$log->debug($image);
  my $meta = {
      artist  => $info->{'subsonic-response'}->{'song'}->{'artist'},
      album   => $info->{'subsonic-response'}->{'song'}->{'album'},
      title   => $info->{'subsonic-response'}->{'song'}->{'title'},
      cover   => $image,
  };
  $log->debug(Data::Dump::dump($meta));
  return $meta
}


sub parser {
    my ( $client, $url, $metadata ) = @_;
    return 1;
}

1;
