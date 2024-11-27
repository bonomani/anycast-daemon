package Anycast::State;

use strict;
use warnings;
use JSON qw(decode_json encode_json to_json);
use File::Slurp;
use Anycast::Constants qw(TRUE FALSE);
use Anycast::Utils qw(run_command get_status_message get_status_code);
use Data::Dumper;

sub new {
    my ($class, %args) = @_;
    my $self = {
        state_file => $args{state_file} || '/opt/anycast3/var/anycast_status.json',
        logger     => $args{logger},  # Pass an instance of Anycast::Log
    };
    bless $self, $class;
    return $self;
}

# Load the state file
sub load_state {
    my ($self) = @_;
    $self->{logger}->log_message("DEBUG", "Loading state from $self->{state_file}");
    my $state = -f $self->{state_file} ? eval { decode_json(read_file($self->{state_file})) } : {};
    return $state;
}

# Save the state to the state file
sub save_state {
    my ($self, $state) = @_;
    $self->{logger}->log_message("DEBUG", "Saving state to $self->{state_file}");
    write_file($self->{state_file}, to_json($state, { pretty => 1, canonical => 1 }));
    $self->{logger}->log_message("DEBUG", "State saved successfully.");
}

sub map_gateway {
    my ($self, $gateway) = @_;
    return {
        name         => $gateway->{name},
        ip           => $gateway->{ip},
        latency      => $gateway->{latency} + 0,
        loss_percent => $gateway->{loss_percent} + 0,
        status       => $gateway->{status} + 0,
    };
}

sub map_service {
    my ($self, $service) = @_;
    return {
        name      => $service->{name},
        status    => $service->{status} + 0,
        processes => $self->map_entities($service->{processes}, sub {
            return $self->map_process($_);
        }),
    };
}

sub map_process {
    my ($self, $process) = @_;
    return {
        name   => $process->{name},
        status => $process->{status} + 0,
        ports  => $self->map_entities($process->{ports}, sub {
            return $self->map_port($_);
        }),
    };
}

sub map_port {
    my ($self, $port) = @_;
    return {
        name     => $port->{name},
        address  => $port->{address},
        port     => $port->{port} + 0,
        protocol => $port->{protocol},
        status   => $port->{status} + 0,
    };
}

sub map_entities {
    my ($self, $entities, $mapper) = @_;
    return [ map { $mapper->($_) } @$entities ];
}

sub update_state {
    my ($self, $current_state) = @_;

    # Save the updated state
    $self->save_state($current_state);

    # Log the changes for debugging and transparency
    $self->{logger}->log_message("DEBUG", "Updated state saved successfully.");
}

# Analyze state changes and delegate logging
sub analyze_state_changes {
    my ($self, $last_state, $current_state) = @_;
    $self->analyze_entity_changes(
	    #current_entities  => $current_state->{global},
	current_entities  => [$current_state],
	#previous_entities => $last_state->{global},
	previous_entities => [$last_state],
    );
}

# Recursively analyze entities for changes and delegate logging
sub analyze_entity_changes {
    my ($self, %args) = @_;
    my $current_entities  = $args{current_entities} // [];
    my $previous_entities = $args{previous_entities} // [];

    for my $current_entity (@$current_entities) {
	    #exit;
        next unless ref $current_entity eq 'HASH'; # Skip invalid entities

        $current_entity->{name} //= $self->build_entity_identifier($current_entity, $current_entity->{type});
        my ($previous_entity) = grep { $_->{name} eq $current_entity->{name} } @$previous_entities;

        if ($self->has_status_changed($current_entity, $previous_entity)) {
	    $current_entity->{last_changed} = time();
	    #exit;
            $self->log_status_change($current_entity, $previous_entity);
        } else {
		 $current_entity->{last_changed} = $previous_entity->{last_changed} // time();
		 #	 exit;
	}

        # Process nested entities
        for my $nested_key (keys %$current_entity) {
            next unless ref $current_entity->{$nested_key} eq 'ARRAY';
            $self->analyze_entity_changes(
                current_entities  => $current_entity->{$nested_key},
                previous_entities => $previous_entity->{$nested_key} // [],
            );
        }
    }
}

# Check if the status has changed
sub has_status_changed {
    my ($self, $current, $previous) = @_;
    return ($previous->{status} // 'unknown') ne ($current->{status} // 'unknown');
}

# Log a specific status change
sub log_status_change {
    my ($self, $current, $previous) = @_;
    $self->{logger}->log_message(
        "WARN",
        sprintf(
            "%s status changed for %s: %s -> %s",
            ucfirst($current->{type}),
            $current->{name},
            get_status_message($current->{type}, $previous->{status} // 'unknown'),
            get_status_message($current->{type}, $current->{status} // 'unknown'),
        )
    );
}

# Generate a name for an entity based on its type
sub build_entity_identifier {
    my ($self, $entity, $entity_type) = @_;

    if ($entity_type eq 'ports') {
        my $protocol = $entity->{protocol} // 'unknown_protocol';
        my $address  = $entity->{address}  // 'unknown_address';
        my $port     = $entity->{port}     // 'unknown_port';
        return "$protocol://$address:$port";
    }
    elsif ($entity_type eq 'gateways') {
        return $entity->{name} // $entity->{ip} // 'Unnamed Gateway';
    }
    elsif ($entity_type eq 'services') {
        return $entity->{name} // 'Unnamed Service';
    }
    elsif ($entity_type eq 'processes') {
        return $entity->{name} // 'Unnamed Process';
    }
    elsif ($entity_type eq 'global') {
        return $entity->{name} // 'Global Entity';
    }

    return $entity->{name} // 'Unnamed Entity';
}

1;

