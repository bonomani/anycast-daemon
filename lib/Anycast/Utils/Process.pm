package Anycast::Utils::Process;

use strict;
use warnings;
use Anycast::Utils::Network qw(check_ports);

# Constructor
sub new {
    my ($class, %args) = @_;
    my $self = {
        logger => $args{logger},  # Logger object (assumed to be always defined)
    };
    bless $self, $class;
    return $self;
}

# Check if a process is running by its name
sub is_process_running {
    my ($self, $process_name) = @_;

    my $pgrep_cmd = "pgrep -x $process_name > /dev/null 2>&1";
    if (system($pgrep_cmd) == 0) {
        $self->{logger}->log_message("DEBUG", "Process '$process_name' is running");
        return 1;
    } else {
        $self->{logger}->log_message("DEBUG", "Process '$process_name' is not running");
        return 0;
    }
}

# Check if a process is running by its PID file
sub is_pid_running {
    my ($self, $pid_file) = @_;

    unless (-f $pid_file) {
        $self->{logger}->log_message("DEBUG", "PID file $pid_file does not exist.");
        return 0;
    }

    open my $fh, '<', $pid_file or do {
        $self->{logger}->log_message("DEBUG", "Failed to open PID file $pid_file: $!");
        return 0;
    };
    my $pid = <$fh>;
    close $fh;

    chomp $pid;
    unless ($pid =~ /^\d+$/) {
        $self->{logger}->log_message("DEBUG", "Invalid PID format in $pid_file: $pid. Cleaning up.");
        unlink $pid_file;
        return 0;
    }

    if (-d "/proc/$pid") {
        $self->{logger}->log_message("DEBUG", "Process with PID $pid from $pid_file is running.");
        return 1;
    } else {
        $self->{logger}->log_message("DEBUG", "No process found with PID $pid from $pid_file. Cleaning up stale PID file.");
        unlink $pid_file;
        return 0;
    }
}

# Check process status for a list of processes
sub check_process_status {
    my ($self, $processes) = @_;
    my @process_statuses;

    foreach my $process (@$processes) {
        $self->{logger}->log_message("DEBUG", "Checking process: $process->{name}");

        my $process_running = $self->is_process_running($process->{name});
        my $ports_status = exists $process->{ports} ? check_ports($process->{ports}, $self->{logger}) : [];

        my $global_port_status = 1;
        foreach my $port (@$ports_status) {
            if ($port->{status} == 0) {
                $global_port_status = 0;
                last;
            }
        }

        my $global_status = $process_running && $global_port_status ? 1 : 0;

        push @process_statuses, {
            name   => $process->{name},
            status => $global_status,
            ports  => $ports_status,
        };
    }

    return \@process_statuses;
}

# Get the status of a single process
sub process_status {
    my ($self, $process) = @_;

    $self->{logger}->log_message("DEBUG", "Checking process: $process->{name}");

    my $process_running = $self->is_process_running($process->{name});
    my $global_status = $process_running ? 1 : 0;

    return {
        name   => $process->{name},
        status => $global_status,
    };
}

# Check the status of multiple services
sub check_services_status {
    my ($self, $services) = @_;
    my @services_status;

    foreach my $service (@$services) {
        $self->{logger}->log_message("DEBUG", "Checking service: $service->{name}");

        my $process_statuses = $self->check_process_status($service->{processes});
        my $all_processes_running = (scalar(grep { $_->{status} } @$process_statuses) == scalar(@$process_statuses)) ? 1 : 0;

        push @services_status, {
            name      => $service->{name},
            processes => $process_statuses,
            status    => $all_processes_running,
        };
    }

    return \@services_status;
}

# Ensure a process is running
sub ensure_process_running {
    my ($self, %args) = @_;
    my $description  = $args{description};
    my $command      = $args{command};
    my $pid_file     = $args{pid_file};

    # Check if the process is running via PID file
    if ($self->is_pid_running($pid_file)) {
        $self->{logger}->log_message("DEBUG", "$description is already running.");
        return 1; # Process is running
    }

    # Process is not running, attempt to start it
    $self->{logger}->log_message("WARN", "$description is not running. Attempting to start...");
    $self->{logger}->log_message("DEBUG", "Executing command: $command");

    my $status = system("$command > /dev/null 2>&1 &");

    if ($status == 0) {
        $self->{logger}->log_message("DEBUG", "$description started successfully.");
        sleep 1; # Allow process to initialize
        return 1; # Process started successfully
    } else {
        $self->{logger}->log_message("WARN", "Failed to start $description. Exit status: " . ($status >> 8));
        return 0; # Failed to start the process
    }
}

1;

