package Anycast::Utils;

use strict;
use warnings;
use Exporter qw(import);
use Anycast::Constants qw(TRUE FALSE DEFAULT_BIND_ADDRESS DEFAULT_DPINGER_PATH $OPERATIONAL_STATE $STATUS_DEFINITIONS);

our @EXPORT_OK = qw(
    run_command
    get_status_message
    get_status_code
);

sub run_command {
	#my ($self, $cmd) = @_;
    my ($cmd) = @_;
    my $output = `$cmd 2>/dev/null`;
    my $exit_status = $? >> 8;
    return ($exit_status, $output);
}

sub get_status_message {
    my ($entity_type, $status) = @_;
    return $STATUS_DEFINITIONS->{$entity_type}{states}{$status}{status_message};
}

sub get_status_code {
    my ($entity_type, $status) = @_;
    return $STATUS_DEFINITIONS->{$entity_type}{states}{$status}{status_code};
}

1;

