package Anycast;

use strict;
use warnings;
use YAML::XS 'LoadFile';
use Anycast::Load;
use Anycast::Utils::Log;
use Anycast::Constants qw(TRUE FALSE DEFAULT_BIND_ADDRESS DEFAULT_DPINGER_PATH $OPERATIONAL_STATE $STATUS_DEFINITIONS);
use Anycast::State;
use Anycast::Utils::Network;
use Anycast::Utils::Process;
use Anycast::Utils::Dpinger;
use Anycast::Utils::Evaluation;
use Anycast::Xymon;
use Anycast::Routing;
use Data::Dumper;
use Storable qw(dclone);

sub new {
    my ($class, %args) = @_;

    # Initialize logger early
    my $logger = Anycast::Utils::Log->new(
        log_level => $args{log_level} // 'INFO',
        log_file  => $args{log_file} // undef
    );
    $logger->log_message("DEBUG", "Initializing Anycast with early logger.");

    # Load configuration
    my $config_file = $args{config_file} // '/etc/anycast/config.yml';
    my $loader = Anycast::Load->new(
        config_file => $config_file,
        logger      => $logger,
    );

    my $config = eval { $loader->load_config() };
    if ($@) {
        $logger->fatal_error("Failed to load configuration", $@);
    }

    # Reinitialize logger with configuration values
    $logger = Anycast::Utils::Log->new(
        log_level => $config->{log_level} // 'INFO',
        log_file  => $config->{log_file} // undef,
    );

    my $self = {
        config_file  => $config_file,
        state_file   => $config->{state_file} // '/opt/anycast3/var/anycast_status.json',
        log_level    => $config->{log_level} // 'INFO',
        config       => $config,
        logger       => $logger,
        start_time   => time(),
        loader       => $loader,
    };

    bless $self, $class;

    #$self->{controllers_state} = dclone($config->{controllers});

    # Initialize modules
    $self->{state_manager} = Anycast::State->new(
        state_file => $self->{state_file},
        logger     => $logger,
    );

    $self->{xymon} = Anycast::Xymon->new(
        logger => $logger,
        config => $config,
    );

    $self->{routing} = Anycast::Routing->new(
        logger => $logger,
    );

    $self->{network} = Anycast::Utils::Network->new(
        logger => $logger,
    );

    $self->{process} = Anycast::Utils::Process->new(
        logger => $logger,
    );

    $self->{dpinger} = Anycast::Utils::Dpinger->new(
        config  => $config,
        logger  => $logger,
        process => $self->{process},
    );

    $self->{evaluation} = Anycast::Utils::Evaluation->new(
        dpinger => $self->{dpinger},
        process => $self->{process},
        network => $self->{network},
        logger  => $logger,
    );

    $self->{routing}->initialize_anycast($config->{controllers})
    	or $logger->fatal_error("Anycast initialization failed.");

    $logger->log_message("DEBUG", "Anycast initialized successfully.");
    return $self;
}

sub daemon {
    my ($self) = @_;
    my $interval = $self->{config}->{interval} // 10;  # Default to 10 seconds
    $self->{logger}->log_message("INFO", "Starting Anycast daemon with interval: $interval seconds...");

    while (1) {
        eval { $self->monitor() };
        if ($@) {
            $self->{logger}->log_message("ERROR", "An error occurred during monitoring: $@");
        }
        sleep $interval;
    }
}

sub monitor {
    my ($self) = @_;

    my $current_timestamp = time();
    my $last_state = $self->{state} // $self->{state_manager}->load_state();

    # Initialize the current state
    my $current_state = {
        name     => 'global',
        elements => []
    };

    # Process controllers
    my $config_controllers = dclone($self->{config}->{controllers});
    foreach my $controller (@$config_controllers) {
        my $transformed_controller = {
            name     => $controller->{name},
            elements => []
        };

        # Evaluate the service monitoring
        my $evaluated_result;
        if ($controller->{service_monitoring}) {
            $evaluated_result = $self->{evaluation}->evaluate_group($controller->{service_monitoring});
            push @{$transformed_controller->{elements}}, $evaluated_result;
        }


        # Manage routing states and push the result to elements
        if ($controller->{routing}) {
            my $monitoring_status = $evaluated_result->{status} // 0;
            my $managed_state_result = $self->{routing}->manage_anycast_states($controller->{routing}, $monitoring_status);
            push @{ $transformed_controller->{elements} }, {
                name   => "Routing Engine for $controller->{name}",
                type   => "routing",
                status => $managed_state_result,
            };
        }

        push @{ $current_state->{elements} }, $transformed_controller;
    }

    # Evaluate the global state
    $current_state = $self->{evaluation}->evaluate_group($current_state);

    # Update state and send notifications
    $self->{state_manager}->analyze_state_changes($last_state, $current_state);
    $self->{state_manager}->update_state($current_state);
    $self->{xymon}->send_xymon_notification($current_state);
    $self->{state} = $current_state;

    $self->{logger}->log_message("DEBUG", "Monitor cycle completed successfully.");
}

1;

