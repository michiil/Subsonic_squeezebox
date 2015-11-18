package Plugins::Subsonic::Metadata;

use strict;

use Slim::Formats::RemoteMetadata;
use JSON::XS::VersionOneAndTwo;
use Slim::Music::Info;

use Slim::Utils::Log;
use Slim::Utils::Prefs;
use URI;
use Plugins::Subsonic::API;

my $prefs = preferences('plugin.subsonic');
my $log = logger('plugin.subsonic');

use constant ICON       => 'plugins/Subsonic/html/images/subsonic.png';

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

sub defaultMeta {
	my ( $client, $url ) = @_;

	return {
		title => Slim::Music::Info::getCurrentTitle($url),
		icon  => ICON,
		type  => $client->string('RADIO'),
		ttl   => time() + 30,
	};
}

sub provider {
	my ( $client, $url ) = @_;

	if ( !$client->isPlaying && !$client->isPaused ) {
		return defaultMeta( $client, $url );
	}

	if ( my $meta = $client->master->pluginData('metadata') ) {

		if ( $meta->{_url} eq $url ) {
			$meta->{title} ||= Slim::Music::Info::getCurrentTitle($url);

			# need to refresh meta data
			if ($meta->{ttl} < time()) {
				fetchMetadata( $client, $url );
			}

			return $meta;
		}

	}

	if ( !$client->master->pluginData('fetchingMeta') ) {
		fetchMetadata( $client, $url );
	}

	return defaultMeta( $client, $url );
}

sub fetchMetadata {
	my ( $client, $url ) = @_;

	return unless $client;

	Slim::Utils::Timers::killTimers( $client, \&fetchMetadata );

	# Make sure client is still playing this song
	if ( Slim::Player::Playlist::url($client) ne $url ) {
		main::DEBUGLOG && $log->is_debug && $log->debug( $client->id . " no longer playing $url, stopping metadata fetch" );
		return;
	}

	$client->master->pluginData( fetchingMeta => 1 );

	my $uri = URI->new($url);
  my %query = $uri->query_form;

	# SN URL to fetch track info menu
	my $metaUrl = $prefs->get('baseurl') . 'rest/getSong.view' . '?u=' . $prefs->get('username') . '&t=' . $prefs->get('passtoken') . '&s=' . $prefs->get('salt') . '&v=1.13.0&c=squeezebox&f=json&id=' . $query{'id'};

	main::DEBUGLOG && $log->is_debug && $log->debug( "Fetching Subsonic metadata from $metaUrl" );

	my $http = Slim::Networking::SimpleAsyncHTTP->new(
		\&_gotMetadata,
		\&_gotMetadataError,
		{
			client     => $client,
			url        => $url,
			timeout    => 30,
		},
	);

	$http->get( $metaUrl );
}

sub _gotMetadata {
	my $http   = shift;
	my $client = $http->params('client');
	my $url    = $http->params('url');

	my $feed = eval { from_json( $http->content ) };

	if ( $@ ) {
		$http->error( $@ );
		_gotMetadataError( $http );
		return;
	}

	if ( main::DEBUGLOG && $log->is_debug ) {
		$log->debug( "Raw Subsonic metadata: " . Data::Dump::dump($feed) );
	}

	my $meta = defaultMeta( $client, $url );
	$meta->{_url} = $url;

	my $image = Plugins::Subsonic::API->getcoverArt($feed->{'subsonic-response'}->{'song'}->{'coverArt'}) || 'html/images/playlists.png';
  #$log->debug($image);
  my $meta = {
      artist  => $feed->{'subsonic-response'}->{'song'}->{'artist'},
      album   => $feed->{'subsonic-response'}->{'song'}->{'album'},
      title   => $feed->{'subsonic-response'}->{'song'}->{'title'},
      httpCover   => $image,
  };

	if ($meta->{ttl} < time()) {
		$meta->{ttl} = time() + ($meta->{ttl} || 60);
	}

	if ( main::DEBUGLOG && $log->is_debug ) {
		$log->debug( "Subsonic metadata: " . Data::Dump::dump($meta) );
	}

	$client->master->pluginData( fetchingMeta => 0 );
	$client->master->pluginData( metadata => $meta );

	Slim::Control::Request::notifyFromArray( $client, [ 'newmetadata' ] );

	Slim::Utils::Timers::setTimer(
		$client,
		$meta->{ttl},
		\&fetchMetadata,
		$url,
	);
}

sub _gotMetadataError {
	my $http   = shift;
	my $client = $http->params('client');
	my $url    = $http->params('url');
	my $error  = $http->error;

	main::DEBUGLOG && $log->is_debug && $log->debug( "Error fetching Subsonic metadata: $error" );

	$client->master->pluginData( fetchingMeta => 0 );

	# To avoid flooding the RT servers in the case of errors, we just ignore further
	# metadata for this station if we get an error
	my $meta = defaultMeta( $client, $url );
	$meta->{_url} = $url;

	$client->master->pluginData( metadata => $meta );

	Slim::Control::Request::notifyFromArray( $client, [ 'newmetadata' ] );

	Slim::Utils::Timers::setTimer(
		$client,
		$meta->{ttl},
		\&fetchMetadata,
		$url,
	);
}

sub parser {
    my ( $client, $url, $metadata ) = @_;
		if ( main::DEBUGLOG && $log->is_debug ) {
			$log->debug( "Parser wird gerufen" );
		}
    return 1;
}

1;
