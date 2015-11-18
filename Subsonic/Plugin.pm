package Plugins::Subsonic::Plugin;

use strict;
use base qw(Slim::Plugin::OPMLBased);

use Slim::Formats::RemoteMetadata;
use Slim::Player::ProtocolHandlers;
use Slim::Utils::Log;
use Slim::Utils::Prefs;
use Slim::Utils::Strings qw(string cstring);

use Plugins::Subsonic::API;

my $prefs = preferences('plugin.subsonic');

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


#	Slim::Control::Request::addDispatch(['subsonic', 'playalbum'], [1, 0, 0, \&cliSubsonicPlayAlbum]);
#	Slim::Control::Request::addDispatch(['subsonic', 'addalbum'], [1, 0, 0, \&cliSubsonicPlayAlbum]);

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
			name => cstring($client, 'PLUGIN_SUBSONIC_ARTISTS'),
			url  => \&SubsonicArtists,
			image => 'html/images/artists.png',
		},{
			name => cstring($client, 'PLUGIN_SUBSONIC_PLAYLISTS'),
			url  => \&SubsonicPlaylists,
			image => 'html/images/playlists.png'
		}] : [{
			name => cstring($client, 'PLUGIN_SUBSONIC_REQUIRES_SETTINGS'),
			type => 'textarea',
		}]
	});
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
		type  => 'playlist',
	};
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

1;
