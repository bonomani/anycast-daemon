
package Anycast::Utils::Network;

use strict;
use warnings;
use Anycast::Utils::Log;

# Constructor
sub new {
    my ($class, %args) = @_;
    my $self = {
        logger => $args{logger}, # Logger object (assumed to be always defined)
    };
    bless $self, $class;
    return $self;
}

# Match a hex address to an expected address
sub match_address {
    my ($self, $hex_address, $expected_address) = @_;

    # Convert hex address to human-readable IP
    my @bytes = reverse map { hex($_) } ($hex_address =~ /(..)/g);
    my $converted_address = join('.', @bytes);

    $self->{logger}->log_message(
        "DEBUG",
        "Comparing converted address $converted_address with expected address $expected_address"
    );

    return $converted_address eq $expected_address;
}

# Check if a port is open
sub is_port_open {
    my ($self, $address, $port, $protocol) = @_;

    # Validate protocol
    my %protocol_file = (
        tcp  => "/proc/net/tcp",
        tcp6 => "/proc/net/tcp6",
        udp  => "/proc/net/udp",
        udp6 => "/proc/net/udp6",
    );

    unless (exists $protocol_file{$protocol}) {
        $self->{logger}->log_message("WARN", "Unsupported protocol: $protocol");
        return 0;
    }

    $self->{logger}->log_message(
        "DEBUG",
        "Reading socket table from $protocol_file{$protocol}"
    );

    # Read socket table for the specified protocol
    open my $fh, '<', $protocol_file{$protocol} or do {
        $self->{logger}->log_message("WARN", "Failed to read $protocol_file{$protocol}: $!");
        return 0;
    };

    my @matching_sockets;

    while (<$fh>) {
        next if $. == 1; # Skip header
        my ($local_address, $state) = (split)[1, 3];
        $self->{logger}->log_message("DEBUG", "Parsed line: local_address=$local_address, state=$state");

        # Check state (0A for TCP LISTEN, 07 for UDP)
        my $expected_state = $protocol =~ /tcp/ ? "0A" : "07";
        next unless $state eq $expected_state;

        my ($ip, $p) = split(/:/, $local_address);
        $p = hex($p); # Convert port to decimal

        # Match address and port
        if ($self->match_address($ip, $address) && $p == $port) {
            $self->{logger}->log_message(
                "DEBUG",
                "Found matching socket: $address:$port/$protocol in $protocol_file{$protocol}"
            );
            push @matching_sockets, {
                address  => $address,
                port     => $port,
                protocol => $protocol,
            };
        }
    }

    close $fh;

    # Log the results
    if (@matching_sockets) {
        $self->{logger}->log_message(
            "DEBUG",
            "Found " . scalar(@matching_sockets) . " matching socket(s) for $address:$port/$protocol"
        );
        return 1; # Port is open
    } else {
        $self->{logger}->log_message(
            "DEBUG",
            "No matching socket found for $address:$port/$protocol"
        );
        return 0; # Port is not open
    }
}

# Check multiple ports
sub check_ports {
    my ($self, $ports) = @_;
    my @ports_status;

    foreach my $port (@$ports) {
        $self->{logger}->log_message(
            "DEBUG",
            "Checking port: $port->{address}:$port->{port}/$port->{protocol}"
        );

        # Check port availability
        my $port_open = $self->is_port_open(
            $port->{address}, $port->{port}, $port->{protocol}
        );

        # Log the result of the port check
        $self->{logger}->log_message(
            "DEBUG",
            "Port check result for $port->{address}:$port->{port}/$port->{protocol}: $port_open"
        );

        # Store the status in the ports array
        push @ports_status, {
            address  => $port->{address},
            port     => $port->{port},
            protocol => $port->{protocol},
            status   => $port_open,
        };
    }

    return \@ports_status;
}

# Check the status of a single port
sub port_status {
    my ($self, $port) = @_;

    $self->{logger}->log_message(
        "DEBUG",
        "Checking port: $port->{address}:$port->{port}/$port->{protocol}"
    );

    # Check port availability
    my $port_open = $self->is_port_open(
        $port->{address}, $port->{port}, $port->{protocol}
    );

    # Log the result of the port check
    $self->{logger}->log_message(
        "DEBUG",
        "Port check result for $port->{address}:$port->{port}/$port->{protocol}: $port_open"
    );

    # Return the status of the single port
    return {
        name     => $port->{name},
        address  => $port->{address},
        port     => $port->{port},
        protocol => $port->{protocol},
        status   => $port_open,
    };
}

1;

