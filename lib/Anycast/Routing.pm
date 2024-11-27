
package Anycast::Routing;

use strict;
use warnings;
use Exporter 'import';
use Data::Dumper;

# Exportable functions (Public API)
our @EXPORT_OK = qw(
    manage_anycast_states
    initialize_anycast
);

# Constructor
sub new {
    my ($class, %args) = @_;
    my $self = {
        logger => $args{logger}, # Expect a logger object
    };
    bless $self, $class;
    return $self;
}

# Public API: Manage OSPF configurations for enabling or disabling anycast
sub manage_anycast_states {
    my ($self, $configurations, $enable) = @_;

    unless (ref($configurations) eq 'ARRAY') {
        $self->{logger}->log_message("ERROR", "Invalid configurations format: Expected an array reference.");
        return undef;
    }

    my $overall_state = 1; # Default to success

    foreach my $ospf (@$configurations) {
        unless (ref($ospf) eq 'HASH') {
            $self->{logger}->log_message("ERROR", "Invalid OSPF configuration: Expected a hash reference.");
            $overall_state = undef;
            next;
        }

        my $routing_type = $ospf->{routing_type};
        my $ip_mask      = $ospf->{ip_mask};
        my $area         = $ospf->{area};
        my $interface    = $ospf->{interface};

        unless (defined $routing_type && $routing_type eq 'ospf') {
            $self->{logger}->log_message("ERROR", "Unsupported or missing routing_type in configuration: " . Dumper($ospf));
            $overall_state = undef;
            next;
        }
        unless (defined $ip_mask && defined $area && defined $interface) {
            $self->{logger}->log_message("ERROR", "Missing required fields in OSPF configuration: " . Dumper($ospf));
            $overall_state = undef;
            next;
        }

        my $result;
        if ($enable) {
            $result = $self->_enable_anycast($ip_mask, $area, $interface);
            $self->{logger}->log_message($result ? "DEBUG" : "ERROR", $result ? "Anycast enabled for $ip_mask." : "Failed to enable anycast for $ip_mask.");
        } else {
            $result = $self->_disable_anycast($ip_mask, $area, $interface);
            $self->{logger}->log_message($result ? "DEBUG" : "ERROR", $result ? "Anycast disabled for $ip_mask." : "Failed to disable anycast for $ip_mask.");
        }

        $overall_state = 0 if !$enable && defined $overall_state && $result == 0;
    }

    return $overall_state;
}

# Public API: Initialize anycast configurations
sub initialize_anycast {
    my ($self, $configurations) = @_;

    $self->{logger}->log_message("DEBUG", "Starting Anycast initialization");

    foreach my $controller (@$configurations) {
        my $controller_name = $controller->{name};
        $self->{logger}->log_message("DEBUG", "Initializing anycast for controller: $controller_name");

        foreach my $route (@{$controller->{routing}}) {
            $self->{logger}->log_message("DEBUG", "Processing routing configuration: " . Dumper($route));

            my $interface = $route->{interface};
            my $ip        = $route->{ip_mask};

            $self->{logger}->log_message("DEBUG", "Checking interface: $interface for IP: $ip");

            my $interface_info = $self->_get_interface_info($interface);
            $self->{logger}->log_message("DEBUG", "Interface info for $interface: " . Dumper($interface_info));

            unless ($self->_check_interface_attribute($interface_info, "line protocol is up")) {
                $self->{logger}->log_message(
                    "WARN",
                    "Interface $interface is not operational. Attempting to bring it up..."
                );

                unless ($self->_bring_interface_up($interface)) {
                    $self->{logger}->log_message("ERROR", "Failed to bring interface $interface up.");
                    return 0;
                }

                $self->{logger}->log_message("DEBUG", "Successfully brought interface $interface up.");
            } else {
                $self->{logger}->log_message("DEBUG", "Interface $interface is operational.");
            }

            unless ($self->_check_interface_attribute($interface_info, $ip)) {
                $self->{logger}->log_message(
                    "WARN",
                    "IP $ip is not assigned to $interface. Assigning IP..."
                );

                unless ($self->_assign_ip_to_interface($ip, $interface)) {
                    $self->{logger}->log_message("ERROR", "Failed to assign IP $ip to interface $interface.");
                    return 0;
                }

                $self->{logger}->log_message("DEBUG", "Successfully assigned IP $ip to interface $interface.");
            } else {
                $self->{logger}->log_message("DEBUG", "IP $ip is already assigned to interface $interface.");
            }
        }
    }

    $self->{logger}->log_message("DEBUG", "All interfaces initialized successfully.");
    return 1;
}


# Internal helper: Execute a vtysh command
sub _execute_vtysh_command {
    my ($self, $command) = @_;
    my $cmd = "sudo vtysh $command";
    my $result = `$cmd 2>&1`;
    if ($? != 0) {
        $self->{logger}->log_message("ERROR", "Command failed: $cmd\nError: $result");
        return undef;
    }
    chomp($result);
    return $result;
}

# Internal helper: Get interface information
sub _get_interface_info {
    my ($self, $interface) = @_;
    return $self->_execute_vtysh_command("-c 'show interface $interface'");
}

# Internal helper: Check if the interface contains a specific attribute
sub _check_interface_attribute {
    my ($self, $interface_info, $pattern) = @_;
    return $interface_info =~ /$pattern/ ? 1 : 0;
}

# Internal helper: Bring the interface up
sub _bring_interface_up {
    my ($self, $interface) = @_;
    return 0 unless defined $self->_modify_interface($interface, "no shutdown");
    return $self->_retry_check(sub { $self->_check_interface_attribute($self->_get_interface_info($interface), "line protocol is up") });
}

# Internal helper: Modify the interface
sub _modify_interface {
    my ($self, $interface, $config_command) = @_;
    $self->{logger}->log_message("DEBUG", "Configuring interface $interface with command: $config_command");
    return $self->_execute_vtysh_command("-c 'configure terminal' -c 'interface $interface' -c '$config_command'");
}

# Internal helper: Retry logic for checking if a condition is met
sub _retry_check {
    my ($self, $check_func, $max_retries) = @_;
    $max_retries ||= 3;
    my $retry_count = 0;

    while ($retry_count < $max_retries) {
        return 1 if $check_func->();
        sleep(1);
        $retry_count++;
    }
    return 0;
}

# Internal helper: Assign IP to the interface if needed
sub _assign_ip_to_interface {
    my ($self, $ip, $interface) = @_;
    return 0 unless defined $self->_modify_interface($interface, "ip address $ip");
    return $self->_retry_check(sub { $self->_check_interface_attribute($self->_get_interface_info($interface), $ip) });
}

# Internal helper: Enable anycast
sub _enable_anycast {
    my ($self, $ip_mask, $area, $interface) = @_;
    return 1 if $self->_check_ip_in_ospf_route($ip_mask, $area, $interface);
    return 0 unless $self->_activate_ospf_on_interface($interface, $area);
    return $self->_check_ip_in_ospf_route($ip_mask, $area, $interface);
}

# Internal helper: Disable anycast
sub _disable_anycast {
    my ($self, $ip_mask, $area, $interface) = @_;
    return 1 unless $self->_check_ip_in_ospf_route($ip_mask, $area, $interface);
    return 0 unless $self->_deactivate_ospf_on_interface($interface, $area);
    return !$self->_check_ip_in_ospf_route($ip_mask, $area, $interface);
}

# Internal helper: Check if the IP is in the OSPF route
sub _check_ip_in_ospf_route {
    my ($self, $ip, $area, $interface) = @_;
    my $result = $self->_execute_vtysh_command("-c 'show ip ospf route'");
    return ($result =~ /$ip[^\n]*area: $area[^\n]*\n[^\n]*directly attached to $interface/) ? 1 : 0;
}

1;

