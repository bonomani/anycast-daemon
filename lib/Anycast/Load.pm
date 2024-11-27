package Anycast::Load;

use strict;
use warnings;
use YAML::XS 'LoadFile';
use Data::Dumper;

sub new {
    my ($class, %args) = @_;

    my $self = {
        config_file => $args{config_file},
        logger      => $args{logger},
    };

    bless $self, $class;

    $self->{logger}->log_message("DEBUG", "Initialized Anycast::Load module.") if $self->{logger};

    return $self;
}

sub load_config {
    my ($self) = @_;
    my $config_file = $self->{config_file};
    my $logger      = $self->{logger};

    unless ($config_file && -f $config_file) {
        $logger->fatal_error("Configuration file not found", $config_file);
    }

    my $config = LoadFile($config_file);
    $self->_resolve_placeholders($config, {
        '{{ runtime_base_dir }}' => $config->{runtime_base_dir} // '',
        '{{ static_base_dir }}'  => $config->{static_base_dir}  // '',
    });

    $logger->log_message("DEBUG", "Resolved configuration: " . Dumper($config)) if $logger;

    $self->_validate_config($config);

    $logger->log_message("DEBUG", "Configuration loaded successfully from $config_file") if $logger;
    return $config;
}

sub _resolve_placeholders {
    my ($self, $config, $placeholders) = @_;

    foreach my $key (keys %$config) {
        $config->{$key} = $self->_replace_placeholder($config->{$key}, $placeholders);
    }

    return $config;
}

sub _replace_placeholder {
    my ($self, $value, $placeholders) = @_;

    if (ref $value eq 'HASH') {
        foreach my $key (keys %$value) {
            $value->{$key} = $self->_replace_placeholder($value->{$key}, $placeholders);
        }
    } elsif (ref $value eq 'ARRAY') {
        @$value = map { $self->_replace_placeholder($_, $placeholders) } @$value;
    } elsif (!ref $value) {
        foreach my $placeholder (keys %$placeholders) {
            $value =~ s/\Q$placeholder\E/$placeholders->{$placeholder}/g if defined $value;
        }
    }

    return $value;
}

sub _validate_config {
    my ($self, $config) = @_;

    my $logger = $self->{logger};
    my @required_keys = qw(
        dpinger.exec_path dpinger.bind_address dpinger.send_interval
        dpinger.loss_interval dpinger.time_period dpinger.report_interval
        dpinger.latency_high dpinger.loss_high state_file xymon.server_ip
    );

    my @missing_keys = grep { !$self->_get_nested_value($config, $_) } @required_keys;

    if (@missing_keys) {
        my $error_msg = "Missing critical configuration keys: " . join(', ', @missing_keys);
        $logger->fatal_error($error_msg);
    }

    $self->_validate_services($config->{services});
    $self->_validate_anycast_crtlds($config->{anycast_crtlds});

    $logger->log_message("DEBUG", "Configuration validated successfully.") if $logger;
}

sub _validate_anycast_crtlds {
    my ($self, $anycast_crtlds) = @_;
    my %names;

    foreach my $crtld (@$anycast_crtlds) {
        if ($names{$crtld->{name}}++) {
            $self->{logger}->fatal_error("Duplicate anycast_crtld name found", $crtld->{name});
        }
        $self->_validate_services($crtld->{services});
    }
}

sub _validate_services {
    my ($self, $services) = @_;
    my %names;

    foreach my $service (@$services) {
        if ($names{$service->{name}}++) {
            $self->{logger}->fatal_error("Duplicate service name found", $service->{name});
        }
        $self->_validate_processes($service->{processes});
    }
}

sub _validate_processes {
    my ($self, $processes) = @_;

    foreach my $process (@$processes) {
        if (exists $process->{ports}) {
            $self->_validate_ports($process->{ports}, $process->{name});
        }
    }
}

sub _validate_ports {
    my ($self, $ports, $process_name) = @_;

    foreach my $port (@$ports) {
        unless (exists $port->{address} && $port->{port} && $port->{protocol}) {
            $self->{logger}->fatal_error(
                "Missing required keys in port configuration",
                "Process: $process_name"
            );
        }

        if ($port->{port} !~ /^\d+$/ || $port->{port} < 1 || $port->{port} > 65535) {
            $self->{logger}->fatal_error(
                "Invalid port number",
                "Process: $process_name, Port: $port->{port}"
            );
        }

        unless ($port->{protocol} =~ /^(tcp|udp)$/) {
            $self->{logger}->fatal_error(
                "Invalid protocol",
                "Process: $process_name, Protocol: $port->{protocol}"
            );
        }

        unless ($port->{address} =~ /^(?:\d{1,3}\.){3}\d{1,3}$|(?:[a-fA-F0-9:]+)$/) {
            $self->{logger}->fatal_error(
                "Invalid address",
                "Process: $process_name, Address: $port->{address}"
            );
        }
    }
}

sub _get_nested_value {
    my ($self, $config, $key_path) = @_;
    my @keys = split(/\./, $key_path);
    my $value = $config;

    foreach my $key (@keys) {
        return undef unless ref $value eq 'HASH' && exists $value->{$key};
        $value = $value->{$key};
    }

    return $value;
}

1;

