package Anycast::Utils::Evaluation;

use strict;
use warnings;
use Anycast::Constants qw($STATUS_DEFINITIONS);
use Anycast::Utils::Process qw(process_status);
use Anycast::Utils::Network qw(port_status);
use Data::Dumper;

# Ensure the presence of a dpinger object
sub new {
    my ($class, %args) = @_;
    my $self = {
        logger  => $args{logger},
        dpinger => $args{dpinger},  # Expecting dpinger object to be passed during initialization
        process => $args{process}, # Pass the Process object
        network => $args{network},
    };
    bless $self, $class;

    # Validate dpinger object
    unless ($self->{dpinger}) {
        $self->{logger}->log_message("WARN", "Dpinger object is required for Evaluation module");
    }

    return $self;
}

# Evaluate a single element (process, port, gateway, group)
sub evaluate_element {
    my ($self, $element) = @_;

    # Determine the element type and validate
    my $type = $element->{type} //= (exists $element->{elements} ? 'group' : undef);
    unless (exists $STATUS_DEFINITIONS->{$type}) {
        $self->{logger}->log_message(
            "WARN",
            "Unsupported type '$type' encountered. Check STATUS_DEFINITIONS for valid types. Details: " . Dumper($element)
        );
        return;
    }

    # If status is already defined, enrich status_message
    if (defined $element->{status}) {
        $element->{status_message} //= $STATUS_DEFINITIONS->{$type}{states}{$element->{status}}{status_message} // 'Unknown status';
        return $element;  # Return early as no further evaluation is needed
    }

    # Initialize result reference for evaluation
    my $res_ref;

    # Handle type-specific evaluation
    if ($type eq "group") {
        return $self->evaluate_group($element);
    } elsif ($type eq "process") {
        $res_ref = $self->{process}->process_status($element);
    } elsif ($type eq "port") {
        $res_ref = $self->{network}->port_status($element);
    } elsif ($type eq "gateway") {
        $res_ref = $self->{dpinger}->gateway_status($element);  # Assuming dpinger object has a gateway_status method
    } else {
        $self->{logger}->log_message(
            "WARN",
            "Unexpected type '$type' during evaluation. Details: " . Dumper($element)
        );
        return;
    }

    # Enrich the element with status message if evaluation succeeded
    if ($res_ref) {
        $element = {
            %{ $res_ref },
            type           => $type,
            status_message => $STATUS_DEFINITIONS->{$type}{states}{$res_ref->{status}}{status_message} // 'Unknown status',
        };
    }

    return $element;
}

# Evaluate a group of elements
sub evaluate_group {
    my ($self, $group) = @_;

    # Validate group structure
    unless ($group && ref $group eq 'HASH' && ref $group->{elements} eq 'ARRAY' && @{ $group->{elements} }) {
        $self->{logger}->log_message(
            "WARN",
            "Invalid group structure. Expected a HASH with a non-empty 'elements' array. Received: " . Dumper($group)
        );
        return;
    }

    my $status = $group->{status};

    # Evaluate elements if status is not already defined
    unless (defined $status) {
        $group->{type}     //= 'group';
        $group->{operator} //= 'all';

        my @evaluated_elements;
        for my $element (@{ $group->{elements} }) {
            push @evaluated_elements, $self->evaluate_element($element);
        }

        my $operator = $group->{operator} eq 'all' ? "AND" : "OR";
        $status = $self->calculate_group_status(\@evaluated_elements, $operator);

        $self->{logger}->log_message(
            "DEBUG",
            "Evaluated group '$group->{name}' with operator '$operator': status $status"
        );

        $group->{elements} = \@evaluated_elements;
    }

    return {
        name           => $group->{name},
        type           => $group->{type},
        operator       => $group->{operator},
        status         => $status,
        status_message => $STATUS_DEFINITIONS->{group}{states}{$status}{status_message},
        elements       => $group->{elements},
    };
}

# Calculate the overall status of a group
sub calculate_group_status {
    my ($self, $statuses, $operator) = @_;

    # Validate input
    unless ($statuses && ref $statuses eq 'ARRAY' && @$statuses) {
        $self->{logger}->log_message(
            "WARN",
            "'statuses' must be a non-empty array reference. Received: " . Dumper($statuses)
        );
        return;
    }

    my %valid_operators = map { $_ => 1 } qw(AND OR);
    unless ($valid_operators{$operator}) {
        $self->{logger}->log_message(
            "WARN",
            "Unsupported operator '$operator'. Supported operators are: " . join(", ", keys %valid_operators)
        );
        return;
    }

    my $count_active = scalar(grep { $_->{status} == 1 } @$statuses);
    my $count_total  = scalar(@$statuses);

    $self->{logger}->log_message(
        "DEBUG",
        "Calculating group status with operator '$operator': $count_active active out of $count_total"
    );

    return $operator eq "AND" ? ($count_active == $count_total ? 1 : 0)
                              : ($count_active > 0             ? 1 : 0);
}

1;

