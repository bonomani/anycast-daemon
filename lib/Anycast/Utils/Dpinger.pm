package Anycast::Utils::Dpinger;

use strict;
use warnings;
use Anycast::Constants qw(DEFAULT_BIND_ADDRESS DEFAULT_DPINGER_PATH);
use Anycast::Utils qw(run_command);
use Anycast::Utils::Process qw(ensure_process_running);

# Constructor
sub new {
    my ($class, %args) = @_;
    my $self = {
        config => $args{config},  # Configuration for dpinger
        logger => $args{logger},  # Logger object
	process => $args{process}, # Process object
    };
    bless $self, $class;
    return $self;
}

# Build the dpinger command
sub build_dpinger_command {
    my ($self, $gateway) = @_;
    my $config = $self->{config}->{dpinger};

    my $output_dir   = $config->{output_dir};
    my $bind_address = $config->{bind_address} // DEFAULT_BIND_ADDRESS;
    my $exec_path    = $config->{exec_path} // DEFAULT_DPINGER_PATH;

    return "$exec_path -B $bind_address " .
           "-s $config->{send_interval} " .
           "-l $config->{loss_interval} " .
           "-t $config->{time_period} " .
           "-r $config->{report_interval} " .
           "-u $output_dir/dpinger-$gateway.sock " .
           "-p $output_dir/dpinger-$gateway.pid $gateway";
}

# Check the status of a gateway
sub gateway_status {
    my ($self, $gateway) = @_;
    my $logger  = $self->{logger};
    my $config  = $self->{config};

    my $gateway_name = $gateway->{name};
    my $gateway_ip   = $gateway->{ip};

    $logger->log_message("DEBUG", "Checking gateway: $gateway_name");

    # Define the PID file for dpinger
    my $pid_file = "$config->{dpinger}->{output_dir}/dpinger-$gateway_ip.pid";

    # Ensure dpinger is running
    my $start_command = $self->build_dpinger_command($gateway_ip);
    $self->{process}->ensure_process_running(
    description  => "dpinger for $gateway_name",
    command      => $start_command,
    pid_file     => $pid_file,
);

    # Read dpinger output
    my ($nc_status, $nc_output) = run_command(
        "nc -U $config->{dpinger}->{output_dir}/dpinger-$gateway_ip.sock"
    );

    # Evaluate the gateway's status
    my $gateway_status = $self->evaluate_gateway_status(
        $gateway,
        $nc_status,
        $nc_output
    );

    $logger->log_message("DEBUG", "Completed check for gateway: $gateway_name.");
    return $gateway_status;
}

# Evaluate the status of a gateway
sub evaluate_gateway_status {
    my ($self, $gateway, $nc_status, $nc_output) = @_;
    my $logger  = $self->{logger};
    my $config  = $self->{config};
    my $gateway_name = $gateway->{name};
    my $gateway_ip   = $gateway->{ip};

    if ($nc_status == 0 && $nc_output =~ /^\d+\s+\d+\s+\d+$/) {
        my ($latency, $jitter, $loss) = map { $_ // 0 } split(/\s+/, $nc_output);
        my $latency_ms = $latency / 1000;

        $logger->log_message("DEBUG",
            "Gateway $gateway_name($gateway_ip) status: Latency=$latency, Jitter=$jitter, Loss=$loss");

        return {
            name         => $gateway_name,
            ip           => $gateway_ip,
            latency      => $latency_ms,
            loss_percent => $loss,
            status       => ($latency_ms <= $config->{dpinger}->{latency_high}
                             && $loss <= $config->{dpinger}->{loss_high}) ? 1 : 0,
        };
    } else {
        $logger->log_message("DEBUG",
            "Failed to read dpinger output for $gateway_name($gateway_ip). Output: $nc_output");

        return {
            name         => $gateway_name,
            ip           => $gateway_ip,
            latency      => -1,
            loss_percent => -1,
            status       => 0,
        };
    }
}

1;

