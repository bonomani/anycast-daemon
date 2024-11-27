package Anycast::Xymon;

use strict;
use warnings;
use POSIX qw(strftime);
use Exporter qw(import);
use Sys::Hostname;
use Anycast::Constants qw(TRUE FALSE DEFAULT_BIND_ADDRESS DEFAULT_DPINGER_PATH $OPERATIONAL_STATE);
use Anycast::Utils qw(run_command get_status_message get_status_code);
use Data::Dumper;

our @EXPORT_OK = qw(
    prepare_xymon_summary
    send_xymon_notification
);

sub new {
    my ($class, %args) = @_;

    my $self = {
        logger => $args{logger},
        config => $args{config},
    };

    bless $self, $class;

    $self->{logger}->log_message("DEBUG", "Initialized Anycast::Xymon module.") if $self->{logger};
    return $self;
}

sub prepare_xymon_summary {
    my ($self, $current_state) = @_;

    $self->{logger}->log_message("DEBUG", "Preparing Xymon summary report...");

    # Generate the global header with status and timestamp
    my $header = $self->_generate_xymon_header($current_state);

    # Initialize the summary
    my $summary = "";

    # Process each anycast control domain, sorted alphabetically by name
    foreach my $ctrld (sort { ($a->{name} // '') cmp ($b->{name} // '') } @{$current_state->{elements}}) {
        $summary .= $self->_generate_recursive_summary($ctrld, 1);
    }

    $self->{logger}->log_message("DEBUG", "Xymon summary prepared successfully.");

    return $header . $summary;
}

sub _generate_xymon_header {
    my ($self, $global_state) = @_;

    my $formatted_current_time = strftime("%a %b %d %H:%M:%S %Y", localtime(time));
    my $formatted_last_changed = strftime("%a %b %d %H:%M:%S %Y", localtime($global_state->{last_changed}));
    my $color = $global_state->{status} ? "&green" : "&red";

    return "<h3>$formatted_current_time - Anycast Global Status</h3>\n"
        . "$color Global Status: " . get_status_message('group', $global_state->{status})
        . ": " . get_status_code('group', $global_state->{status})
        . "\nLast check: $formatted_current_time"
        . "\nLast changed: $formatted_last_changed\n\n";
}

sub _generate_recursive_summary {
    my ($self, $entity, $depth) = @_;

    my $summary = "";
    my $indent  = "&nbsp;" x ($depth * 3); # Indentation based on depth

    # Process the current entity's attributes
    my $entity_name  = $entity->{name} // 'Unnamed Entity';
    my $entity_color = $entity->{status} ? "&green" : "&red";
    my $entity_type = $entity->{type};
    $summary .= "$indent$entity_color $entity_name " . get_status_message($entity_type, $entity->{status}) . ": " . get_status_code($entity_type, $entity->{status}) . "\n";

    # Dynamically process nested keys
    foreach my $key (sort keys %$entity) {
        next unless ref $entity->{$key};    # Only process references (arrays or hashes)

        if (ref $entity->{$key} eq 'ARRAY') {
            foreach my $child_entity (@{ $entity->{$key} }) {
                $summary .= $self->_generate_recursive_summary($child_entity, $depth + 1);
            }
        } elsif (ref $entity->{$key} eq 'HASH') {
            foreach my $child_name (sort keys %{ $entity->{$key} }) {
                $summary .= $self->_generate_recursive_summary($entity->{$key}{$child_name}, $key, $depth + 1);
            }
        }
    }

    return $summary;
}

sub send_xymon_notification {
    my ($self, $current_state) = @_;

    $self->{logger}->log_message("DEBUG", "Sending Xymon notification...");

    my $global_status = $current_state->{global}[0]{status};

    # Determine the color based on the current operational status
    my $color = $global_status ? "green" : "red";

    unless ($color =~ /^(green|yellow|red)$/) {
        $self->{logger}->log_message("ERROR", "Invalid color: $color");
        return;
    }

    my $summary = $self->prepare_xymon_summary($current_state);

    my $short_hostname = hostname();
    $short_hostname =~ s/\..*//;

    my $xymon_command = "/usr/lib/xymon/client/bin/xymon $self->{config}->{xymon}->{server_ip} "
        . "\"status $short_hostname.anycast $color\n$summary\"";

    $self->{logger}->log_message("DEBUG", "Executing command: $xymon_command");
    my ($cmd_status, $output) = run_command($xymon_command);

    if ($cmd_status != 0) {
        $self->{logger}->log_message("WARN", "Failed to send notification to Xymon: Exit Status: $cmd_status | Output: " . ($output || "No output"));
        return;
    }

    $self->{logger}->log_message("DEBUG", "Notification sent to Xymon successfully.");
}

1;

