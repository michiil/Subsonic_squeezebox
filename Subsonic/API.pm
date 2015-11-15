package Plugins::Subsonic::API;

use strict;
use base qw(Slim::Plugin::OPMLBased);

use File::Spec::Functions qw(catdir);
use FindBin qw($Bin);

use JSON::XS::VersionOneAndTwo;
use URI::Escape qw(uri_escape_utf8);
use Digest::MD5 qw(md5_hex);

use Slim::Utils::Cache;
use Slim::Utils::Log;
use Slim::Utils::Prefs;

my $prefs = preferences('plugin.subsonic');
my $log = logger('plugin.subsonic');


sub getcoverArt {
	my ($class, $coverID) = @_;
	my $coverUrl = $prefs->get('baseurl') . 'rest/getCoverArt.view' . '?u=' . $prefs->get('username') . '&t=' . $prefs->get('passtoken') . '&s=' . $prefs->get('salt') . '&v=1.13.0&c=squeezebox&size=400&id=' . $coverID;
	return $coverUrl
}

sub getstreamUrl {
	my ($class, $songId) = @_;
	my $streamUrl = $prefs->get('baseurl') . 'rest/stream.view' . '?u=' . $prefs->get('username') . '&t=' . $prefs->get('passtoken') . '&s=' . $prefs->get('salt') . '&maxBitRate=' . $prefs->get('bitrate') . '&v=1.13.0&c=squeezebox&id=' . $songId;
	return $streamUrl
}

#sub getArtist {
#	my ($class, $cb, $artistId) = @_;
#
#	_get('rest/getArtist.view', sub {
#		my $results = shift;
#		$cb->($results) if $cb;
#	}, {
#		id					=> $artistId,
#		u						=> $prefs->get('username'),
#		t						=> $prefs->get('passtoken'),
#		s						=> $prefs->get('salt'),
#	});
#}

#sub getAlbum {
#	my ($class, $cb, $albumId) = @_;
#
#	_get('rest/getAlbum.view', sub {
#		my $album = shift;
#
#		($album) = @{_precacheAlbum([$album])} if $album;
#
#		$cb->($album);
#	},{
#		album_id => $albumId,
#	});
#}

sub getPlaylists {
	my ($class, $cb, $user) = @_;

	_get('rest/getPlaylists.view', sub {
		my $playlists = shift;

		$cb->($playlists);
	}, {
		u						=> $prefs->get('username'),
		t						=> $prefs->get('passtoken'),
		s						=> $prefs->get('salt'),
	});
}

#sub getArtists {
#	my ($class, $cb, $user) = @_;
#
#	_get('rest/getArtists.view', sub {
#		my $artists = shift;
#
#		$cb->($artists);
#	}, {
#		u						=> $prefs->get('username'),
#		t						=> $prefs->get('passtoken'),
#		s						=> $prefs->get('salt'),
#		_ttl        => USER_DATA_EXPIRY,
#	});
#}

sub getPlaylistTracks {
	my ($class, $cb, $playlistId) = @_;

	_get('rest/getPlaylist.view', sub {
		my $tracks = shift;

		$cb->($tracks);
	},{
		id					=> $playlistId,
		u						=> $prefs->get('username'),
		t						=> $prefs->get('passtoken'),
		s						=> $prefs->get('salt'),
	});
}

#sub getTrackInfo {
#	my ($class, $cb, $trackId) = @_;
#
#	$cb->() unless $trackId;
#
#	my $meta = $cache->get('trackInfo_' . $trackId);
#
#	if ($meta) {
#		$cb->($meta);
#		return $meta;
#	}
#
#	_get('getSong.view', sub {
#		my $meta = shift;
#		$meta = _precacheTrack($meta) if $meta;
#
#		$cb->($meta);
#	},{
#		track_id => $trackId
#	});
#}

#sub getFileUrl {
#	my ($class, $cb, $trackId, $format) = @_;
#	$class->( $baseurl . 'stream.view' . $urlparams . '&id=' . $trackid );
#}

#sub getFileInfo {
#	my ($class, $cb, $trackId, $format, $urlOnly) = @_;
#
#	$cb->() unless $trackId;
#
#	my $bitrate = $prefs->get('bitrate');
#
#	if ( my $cached = $class->getCachedFileInfo($trackId, $urlOnly) ) {
#		$cb->($cached);
#		return $cached
#	}
#
#	_get('track/getFileUrl', sub {
#		my $track = shift;
#
#		if ($track) {
#			my $url = delete $track->{url};
#
#			# cache urls for a short time only
#			$cache->set("trackUrl_${trackId}_$preferredFormat", $url, URL_EXPIRY);
#			$cache->set("trackId_$url", $trackId, DEFAULT_EXPIRY);
#			$cache->set("fileInfo_${trackId}_$preferredFormat", $track, DEFAULT_EXPIRY);
#			$track = $url if $urlOnly;
#		}
#
#		$cb->($track);
#	},{
#		track_id   => $trackId,
#		format_id  => $preferredFormat,
#		_ttl       => URL_EXPIRY,
#		_sign      => 1,
#		_use_token => 1,
#	});
#}

sub _get {
	my ( $url, $cb, $params ) = @_;

	$params ||= {};

	my @query;
	while (my ($k, $v) = each %$params) {
		next if $k =~ /^_/;		# ignore keys starting with an underscore
		push @query, $k . '=' . uri_escape_utf8($v);
	}

	$url = $prefs->get('baseurl') . $url . '?v=1.13.0&c=squeezebox&f=json&' . join('&', sort @query);

	Slim::Networking::SimpleAsyncHTTP->new(
		sub {
			my $response = shift;

			my $result = eval { from_json($response->content) };

			$@ && $log->error($@);
			main::DEBUGLOG && $log->is_debug && $url !~ /getFileUrl/i && $log->debug(Data::Dump::dump($result));

			$cb->($result);
		},
		sub {
			my ($http, $error) = @_;

			#login failed due to invalid username/password: delete password and salt
			if ($error =~ /^40/) {
				$prefs->remove('passtoken');
				$prefs->remove('salt');
			}

			$log->warn("Error: $error");
			$cb->();
		},
		{
			timeout => 15,
		},
	)->get($url);
}

1;
