package Anycast::Constants;

use strict;
use warnings;
use Exporter qw(import);

our @EXPORT_OK = qw(TRUE FALSE DEFAULT_BIND_ADDRESS DEFAULT_DPINGER_PATH $OPERATIONAL_STATE $STATUS_DEFINITIONS);

use constant {
    TRUE  => 1,
    FALSE => 0,
    DEFAULT_BIND_ADDRESS => '0.0.0.0',
    DEFAULT_DPINGER_PATH => '/usr/local/bin/dpinger',
};

our $OPERATIONAL_STATE = {
    gateways => {
        1 => { status_message => "is reachable", status_code => "OK" },
        0 => { status_message => "is unreachable", status_code => "KO" },
    },
    services => {
        1 => { status_message => "is operational", status_code => "OK" },
        0 => { status_message => "is not operational", status_code => "KO" },
    },
    processes => {
        1 => { status_message => "is running", status_code => "OK" },
        0 => { status_message => "is stopped or have port issues", status_code => "KO" },
    },
    ports => {
        1 => { status_message => "is open", status_code => "OK" },
        0 => { status_message => "is closed", status_code => "KO" },
    },
    anycast_ctrlds => {
        1 => { status_message => "is active", status_code => "OK" },
        0 => { status_message => "is inactive", status_code => "KO" },
    },
};

# Status Definitions
our $STATUS_DEFINITIONS = {
    gateway => {
        description => "Evaluate if gateways are operational",
        states      => {
            1 => { status_message => "is reachable", status_code => "OK" },
            0 => { status_message => "is unreachable", status_code => "KO" },
        },
    },
    process => {
        description => "Evaluate if processes are running",
        states      => {
            1 => { status_message => "is running", status_code => "OK" },
            0 => { status_message => "is stopped or has issues", status_code => "KO" },
        },
    },
    port => {
        description => "Evaluate if ports are open",
        states      => {
            1 => { status_message => "is open", status_code => "OK" },
            0 => { status_message => "is closed", status_code => "KO" },
        },
    },
    group => {
        description => "Evaluate groups",
        states      => {
            1 => { status_message => "is operational", status_code => "OK" },
            0 => { status_message => "is not operational", status_code => "KO" },
        },
    },
    routing => {
        description => "Evaluate routing",
        states      => {
            1 => { status_message => "is operational", status_code => "OK" },
            0 => { status_message => "is not operational", status_code => "KO" },
        },
    },
};

1;

