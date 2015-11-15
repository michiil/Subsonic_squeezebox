package Plugins::Subsonic::Plugin;

use strict;
use base qw(Slim::Plugin::OPMLBased);

use Slim::Formats::RemoteMetadata;
use Slim::Player::ProtocolHandlers;
use Slim::Utils::Log;
use Slim::Utils::Prefs;
use Slim::Utils::Strings qw(string cstring);

use Plugins::Subsonic::API;
use Plugins::Subsonic::ProtocolHandler;

my $prefs = preferences('plugin.subsonic');

$prefs->init({
	bitrate => 6,
});

my $log = Slim::Utils::Log->addLogCategory( {
	category     => 'plugin.subsonic',
	defaultLevel => 'ERROR',
	description  => 'PLUGIN_SUBSONIC',
} );

use constant PLUGIN_TAG => 'SUBSONIC';
use constant CAN_IMAGEPROXY => (Slim::Utils::Versions->compareVersions($::VERSION, '7.8.0') >= 0);

sub initPlugin {
	my $class = shift;

	if (main::WEBUI) {
		require Plugins::Subsonic::Settings;
		Plugins::Subsonic::Settings->new();
	}

	Slim::Player::ProtocolHandlers->registerHandler(
		subsonic => 'Plugins::Subsonic::ProtocolHandler'
	);

	Slim::Player::ProtocolHandlers->registerIconHandler(
		qr|\.qobuz\.com/|,
		sub { $class->_pluginDataFor('icon') }
	);

	# Track Info item
	Slim::Menu::TrackInfo->registerInfoProvider( subsonic => (
		func  => \&trackInfoMenu,
	) );

	Slim::Menu::ArtistInfo->registerInfoProvider( subsonic => (
		func => \&artistInfoMenu,
	) );

	Slim::Menu::AlbumInfo->registerInfoProvider( subsonic => (
		func => \&albumInfoMenu,
	) );

	Slim::Menu::GlobalSearch->registerInfoProvider( subsonic => (
		func => \&searchMenu,
	) );

	Slim::Control::Request::addDispatch(['subsonic', 'playalbum'], [1, 0, 0, \&cliSubsonicPlayAlbum]);
	Slim::Control::Request::addDispatch(['subsonic', 'addalbum'], [1, 0, 0, \&cliSubsonicPlayAlbum]);

	# "Local Artwork" requires LMS 7.8+, as it's using its imageproxy.
	if (CAN_IMAGEPROXY) {
		require Slim::Web::ImageProxy;
		Slim::Web::ImageProxy->registerHandler(
			match => qr/static\.qobuz\.com/,
			func  => \&_imgProxy,
		);
	}

	$class->SUPER::initPlugin(
		feed   => \&handleFeed,
		tag    => PLUGIN_TAG,
		menu   => 'radios',
		is_app => 1,
		weight => 1,
	);
}

sub getDisplayName { 'PLUGIN_SUBSONIC' }

# don't add this plugin to the Extras menu
sub playerMenu {}

sub handleFeed {
	my ($client, $cb, $args) = @_;

	my $params = $args->{params};

	$cb->({
		items => ( $prefs->get('username') && $prefs->get('passtoken') && $prefs->get('baseurl') ) ? [{
			name => cstring($client, 'PLUGIN_SUBSONIC_PLAYLISTS'),
			url  => \&SubsonicPlaylists,
			image => 'html/images/playlists.png'
		},{
			name => cstring($client, 'PLUGIN_SUBSONIC_ARTISTS'),
			url  => \&SubsonicArtists,
			image => 'html/images/artists.png',
		}] : [{
			name => cstring($client, 'PLUGIN_SUBSONIC_REQUIRES_SETTINGS'),
			type => 'textarea',
		}]
	});
}

sub SubsonicPlaylists {
	my ($client, $cb, $params, $args) = @_;

	Plugins::Subsonic::API->getPlaylists(sub {
		_playlistCallback(shift, $cb, undef, $params->{isWeb});
	});
}

sub _playlistCallback {
	my ($searchResult, $cb, $showOwner, $isWeb) = @_;

	my $playlists = [];

	for my $playlist ( @{$searchResult->{'subsonic-response'}->{'playlists'}->{'playlist'}} ) {
		next if defined $playlist->{'songCount'} && !$playlist->{'songCount'};
		push @$playlists, _playlistItem($playlist);
	}

	$cb->( {
		items => $playlists
	} );
}

sub SubsonicArtists {
	my ($client, $cb, $params, $args) = @_;

	Plugins::Subsonic::API->getArtists(sub {
		_artistCallback(shift, $cb, undef, $params->{isWeb});
	});
}

sub _artistCallback {
	my ($searchResult, $cb, $showOwner, $isWeb) = @_;

	my $artists = [];

	for my $index ( @{$searchResult->{'subsonic-response'}->{'artists'}->{'index'}} ) {
		for my $artist ( @{$index->{'artist'}} ) {
			next if defined $artist->{'albumCount'} && !$artist->{'albumCount'};
			push @$artists, _artistItem($artist);
		}
	}

	$cb->( {
		items => $artists
	} );
}

sub SubsonicPlaylistGetTracks {
	my ($client, $cb, $params, $args) = @_;
	my $playlistId = $args->{playlist_id};

	Plugins::Subsonic::API->getPlaylistTracks(sub {
		my $playlist = shift;

		if (!$playlist) {
			$log->error("Get playlist ($playlistId) failed");
			return;
		}

		my $tracks = [];

		foreach my $track (@{$playlist->{'subsonic-response'}->{'playlist'}->{'entry'} }) {
			push @$tracks, _trackItem($client, $track);
		}

		$cb->({
			items => $tracks,
		}, @_ );
	}, $playlistId);
}

sub SubsonicAlbumGetTracks {
	my ($client, $cb, $params, $args) = @_;
	my $albumId = $args->{album_id};

	Plugins::Subsonic::API->getAlbumTracks(sub {
		my $album = shift;

		if (!$album) {
			$log->error("Get album ($albumId) failed");
			return;
		}

		my $tracks = [];

		foreach my $track (@{$album->{'subsonic-response'}->{'album'}->{'song'} }) {
			push @$tracks, _trackItem($client, $track);
		}

		$cb->({
			items => $tracks,
		}, @_ );
	}, $albumId);
}

sub SubsonicArtistGetAlbums {
	my ($client, $cb, $params, $args) = @_;
	my $artistId = $args->{artist_id};

	Plugins::Subsonic::API->getArtistAlbums(sub {
		my $artist = shift;

		if (!$artist) {
			$log->error("Get artist ($artistId) failed");
			return;
		}

		my $albums = [];

		foreach my $album (@{$artist->{'subsonic-response'}->{'artist'}->{'album'} }) {
			push @$albums, _albumItem($client, $album);
		}

		$cb->({
			items => $albums,
		}, @_ );
	}, $artistId);
}

sub _playlistItem {
	my ($playlist) = @_;

	my $image = Plugins::Subsonic::API->getcoverArt($playlist->{'coverArt'}) || 'html/images/playlists.png';

	my $owner = $playlist->{'owner'} || undef;

	return {
		name  => $playlist->{'name'},
		name2 => $owner,
		url   => \&SubsonicPlaylistGetTracks,
		image => $image,
		passthrough => [{
			playlist_id  => $playlist->{'id'},
		}],
		type  => 'playlist',
	};
}

sub _artistItem {
	my ($artist) = @_;

	my $image = Plugins::Subsonic::API->getcoverArt($artist->{'coverArt'}) || 'html/images/playlists.png';

	return {
		name  => $artist->{'name'},
		url   => \&SubsonicArtistGetAlbums,
		image => $image,
		passthrough => [{
			artist_id  => $artist->{'id'},
		}],
		type  => 'artist',
	};
}

sub _trackItem {
	my ($client, $track) = @_;

	my $artist = $track->{'artist'} || '';
	my $album  = $track->{'album'} || '';
	my $image = Plugins::Subsonic::API->getcoverArt($track->{'coverArt'}) || 'html/images/playlists.png';
	my $streamUrl = Plugins::Subsonic::API->getstreamUrl($track->{'id'});

	return {
		name  => $track->{'title'},
		line1 => $track->{'title'},
		line2 => $artist . ($artist && $album ? ' - ' : '') . $album,
		image => $image,
		play	=> $streamUrl,
		on_select => 'play',
		playall		=> 1,
	};
}

sub _albumItem {
	my ($client, $album) = @_;

	my $image = Plugins::Subsonic::API->getcoverArt($album->{'coverArt'}) || 'html/images/playlists.png';

	return {
		name  => $album->{'name'},
		url   => \&SubsonicAlbumGetTracks,
		image => $image,
		passthrough => [{
			album_id  => $album->{'id'},
		}],
		type  => 'album',
	};
}

sub trackInfoMenu {
	my ( $client, $url, $track, $remoteMeta, $tags ) = @_;

	my $artist = $track->remote ? $remoteMeta->{artist} : $track->artistName;
	my $album  = $track->remote ? $remoteMeta->{album}  : ( $track->album ? $track->album->name : undef );
	my $title  = $track->remote ? $remoteMeta->{title}  : $track->title;

	my $items;

	if ( my ($trackId) = Plugins::Qobuz::ProtocolHandler->crackUrl($url) ) {
		my $albumId = $remoteMeta ? $remoteMeta->{albumId} : undef;
		my $artistId= $remoteMeta ? $remoteMeta->{artistId} : undef;

		if ($trackId || $albumId || $artistId) {
			my $args = ();
			if ($artistId && $artist) {
				$args->{artistId} = $artistId;
				$args->{artist}   = $artist;
			}

			if ($trackId && $title) {
				$args->{trackId} = $trackId;
				$args->{title}   = $title;
			}

			if ($albumId && $album) {
				$args->{albumId} = $albumId;
				$args->{album}   = $album;
			}

			$items ||= [];
			push @$items, {
				name => cstring($client, 'PLUGIN_QOBUZ_MANAGE_FAVORITES'),
				url  => \&QobuzManageFavorites,
				passthrough => [$args],
			}
		}
	}

	return _objInfoHandler( $client, $artist, $album, $title, $items );
}

sub artistInfoMenu {
	my ($client, $url, $artist, $remoteMeta, $tags, $filter) = @_;

	return _objInfoHandler( $client, $artist->name );
}

sub albumInfoMenu {
	my ($client, $url, $album, $remoteMeta, $tags, $filter) = @_;

	my $albumTitle = $album->title;
	my @artists;
	push @artists, $album->artistsForRoles('ARTIST'), $album->artistsForRoles('ALBUMARTIST');

	return _objInfoHandler( $client, $artists[0]->name, $albumTitle );
}

sub _objInfoHandler {
	my ( $client, $artist, $album, $track, $items ) = @_;

	$items ||= [];

	my %seen;
	foreach ($artist, $album, $track) {
		# prevent duplicate entries if eg. album & artist have the same name
		next if $seen{$_};

		$seen{$_} = 1;

		push @$items, {
			name => cstring($client, 'PLUGIN_QOBUZ_SEARCH', $_),
			url  => \&QobuzSearch,
			passthrough => [{
				q => $_,
			}]
		} if $_;
	}

	my $menu;
	if ( scalar @$items == 1) {
		$menu = $items->[0];
		$menu->{name} = cstring($client, 'PLUGIN_ON_QOBUZ');
	}
	elsif (scalar @$items) {
		$menu = {
			name  => cstring($client, 'PLUGIN_ON_QOBUZ'),
			items => $items
		};
	}

	return $menu if $menu;
}

sub _imgProxy { if (CAN_IMAGEPROXY) {
	my ($url, $spec) = @_;

	#main::DEBUGLOG && $log->debug("Artwork for $url, $spec");

	# https://github.com/Qobuz/api-documentation#album-cover-sizes
	my $size = Slim::Web::ImageProxy->getRightSize($spec, {
		50 => 50,
		160 => 160,
		300 => 300,
		600 => 600
	}) || 'max';

	$url =~ s/(\d{13}_)[\dmax]+(\.jpg)/$1$size$2/ if $size;

	#main::DEBUGLOG && $log->debug("Artwork file url is '$url'");

	return $url;
} }

1;
