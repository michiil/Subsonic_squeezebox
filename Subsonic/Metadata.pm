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

	main::DEBUGLOG && $log->is_debug && $log->debug( "Fetching Subsonic metadata for id $query{'id'}" );

	Plugins::Subsonic::API->gettrackInfo( sub {
		my $info = shift;
		_gotMetadata($info, $client, $url);
	}, $query{'id'} )

}

sub _gotMetadata {
	my ($feed, $client, $url) = @_;

	if ( main::DEBUGLOG && $log->is_debug ) {
		$log->debug( "Raw Subsonic metadata: " . Data::Dump::dump($feed) );
	}

	my $image = Plugins::Subsonic::API->getcoverArt($feed->{'subsonic-response'}->{'song'}->{'coverArt'}) || 'html/images/playlists.png';

	my $meta = defaultMeta( $client, $url );
  $meta = {
      artist  => $feed->{'subsonic-response'}->{'song'}->{'artist'},
      album   => $feed->{'subsonic-response'}->{'song'}->{'album'},
      title   => $feed->{'subsonic-response'}->{'song'}->{'title'},
      Cover   => $image,
			icon		=> $image,
			_url		=> $url,
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

sub parser {
    my ( $client, $url, $metadata ) = @_;
		if ( main::DEBUGLOG && $log->is_debug ) {
			$log->debug( "Parser is called" );
		}
    return 1;
}

1;
