#! /usr/bin/perl -w

use strict;
use warnings;
use Carp;
use IO::Socket::INET;
use JSON;
use CGI qw/-utf8/;

my $q = new CGI;
print $q->header(-type => 'application/json', -expires => 'now');

my $sock;
my $use_sock = 1;

$sock = new IO::Socket::INET (
			      PeerHost => 'localhost',
			      PeerPort => '6693',
			      Proto => 'tcp',
			     ) or die "ERROR in Socket Creation : $!\n";

$| = 1;

my $query = $q->param('q');

$query //= "I need help saving my home.";

print $sock $query . "\n";

my $response = <$sock>;

print $response;
$sock->close();

exit;
