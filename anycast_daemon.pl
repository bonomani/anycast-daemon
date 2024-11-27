#!/usr/bin/perl

use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/lib";
use Anycast;

# Configuration
my $config_file = '/etc/anycast/config.yml';

# Create Anycast object and start the daemon
Anycast->new(config_file => $config_file)->daemon();

