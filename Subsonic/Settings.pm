package Plugins::Subsonic::Settings;

use strict;
use base qw(Slim::Web::Settings);
use Slim::Utils::Prefs;
use Slim::Utils::Log;
use Digest::MD5 qw(md5_hex);


# Used for logging.
my $log = Slim::Utils::Log->addLogCategory({
	'category'     => 'plugin.subsonic',
	'defaultLevel' => 'INFO',
	'description'  => 'Subsonic Settings',
});

my $prefs = preferences('plugin.subsonic');

sub name {
	return Slim::Web::HTTP::CSRF->protectName('PLUGIN_SUBSONIC');
}

sub page {
	return Slim::Web::HTTP::CSRF->protectURI('plugins/Subsonic/settings/basic.html');
}

sub prefs {
	return ($prefs);
}

sub handler {
	my ($class, $client, $params) = @_;

	if ($params->{'saveSettings'} && $params->{'username'}) {

		if ($params->{'baseurl'}) {
			my $baseurl = $params->{'baseurl'};
			$prefs->set('baseurl', "$baseurl"); # add a leading space to make the message display nicely
		}

		if ($params->{'username'}) {
			my $username = $params->{'username'};
			$prefs->set('username', "$username"); # add a leading space to make the message display nicely
		}

		if ($params->{'password'} && ($params->{'password'} ne "****")) {
			my @set = ('0' ..'9', 'A' .. 'Z', 'a' .. 'z');
			my $salt = join '' => map $set[rand @set], 1 .. 8;
			my $passtoken = md5_hex($params->{'password'} . $salt);
			$prefs->set('salt', "$salt");
			$prefs->set('passtoken', "$passtoken"); # add a leading space to make the message display nicely
		}

		if ($params->{'bitrate'}) {
			my $bitrate = $params->{'bitrate'};
			$prefs->set('bitrate', "$bitrate"); # add a leading space to make the message display nicely
		}
	}

	# This puts the value on the webpage.
	# If the page is just being displayed initially, then this puts the current value found in prefs on the page.
	$params->{'prefs'}->{'baseurl'} = $prefs->get('baseurl');
	$params->{'prefs'}->{'username'} = $prefs->get('username');
	$params->{'prefs'}->{'passtoken'} = "****";
	$params->{'prefs'}->{'bitrate'} = $prefs->get('bitrate');

	# I have no idea what this does, but it seems important and it's not plugin-specific.
	return $class->SUPER::handler($client, $params);
}

1;

__END__
