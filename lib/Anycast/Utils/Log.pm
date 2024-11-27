package Anycast::Utils::Log;

use strict;
use warnings;
use POSIX qw(strftime);
use Sys::Syslog qw(:standard :macros);

# Constructor to initialize logger
sub new {
    my ($class, %args) = @_;
    my $self = {
        log_level => $args{log_level} || 'INFO', # Default log level
        log_file  => $args{log_file},           # Log to file if specified
    };

    # Initialize syslog if no log_file is provided
    if (!$self->{log_file}) {
        openlog('Anycast', 'pid', LOG_USER);
        $self->{use_syslog} = 1;
    }

    bless $self, $class;
    return $self;
}

# Centralized logging method
sub log_message {
    my ($self, $level, $message) = @_;
    my %level_priority = (DEBUG => 1, INFO => 2, WARN => 3, ERROR => 4);

    # Validate the current log level and default to INFO if not recognized
    my $current_priority = $level_priority{$self->{log_level}} // 2;

    # Validate the incoming log level and default to ERROR if not recognized
    my $level_priority = $level_priority{$level} // 4;

    # Skip logging if the incoming level is below the current priority
    return if $level_priority < $current_priority;

    # Add context only for DEBUG level
    if ($self->{log_level} eq 'DEBUG') {
        my ($package, $filename, $line, $subroutine) = caller(1);
        $subroutine ||= "unknown";
        $filename ||= "unknown";
        $line ||= "unknown";
        my $context = "$subroutine at $filename line $line";
        $message = "[$context] $message";  # Append context to the message
    }

    # ISO 8601 format for logging
    my $iso_timestamp = strftime("%Y-%m-%dT%H:%M:%S%z", localtime);

    if ($self->{use_syslog}) {
        # Map custom log levels to syslog levels
        my %syslog_levels = (
            DEBUG => LOG_DEBUG,
            INFO  => LOG_INFO,
            WARN  => LOG_WARNING,
            ERROR => LOG_ERR,
        );

        syslog($syslog_levels{$level} // LOG_ERR, "%s", $message);
    } elsif ($self->{log_file}) {
        # Log to file
        my $log_fh;
        if (open $log_fh, '>>', $self->{log_file}) {
            print $log_fh "[$iso_timestamp] [$level] $message\n";
            close $log_fh;
        } else {
            # If log file writing fails, fallback to printing
            print STDERR "[$iso_timestamp] [$level] $message\n";
        }
    } else {
        # Fallback to STDERR if no log_file or syslog
        print STDERR "[$iso_timestamp] [$level] $message\n";
    }
}

# Add this to Log.pm
sub fatal_error {
    my ($self, $message, $details) = @_;
    my $caller_context = (caller(1))[3];  # Get the calling subroutine name
    my $full_message = $details ? "$message. $details" : $message;

    $self->log_message("ERROR", "[$caller_context] $full_message");
    die "Fatal error in $caller_context: $message. See logs for details.";
}


# Destructor to close syslog connection
sub DESTROY {
    my ($self) = @_;
    closelog() if $self->{use_syslog};
}

1;

