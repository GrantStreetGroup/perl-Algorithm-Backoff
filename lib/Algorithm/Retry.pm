package Algorithm::Retry;

# DATE
# VERSION

use 5.010001;
use strict 'subs', 'vars';
use warnings;

use Time::HiRes qw(time);

our %SPEC;

our %attr_max_attempts = (
    max_attempts => {
        summary => 'Maximum number consecutive failures before giving up',
        schema => 'uint*',
        default => 0,
        description => <<'_',

0 means to retry endlessly without ever giving up. 1 means to give up after a
single failure (i.e. no retry attempts). 2 means to retry once after a failure.
Note that after a success, the number of attempts is reset (as expected). So if
max_attempts is 3, and if you fail twice then succeed, then on the next failure
the algorithm will retry again for a maximum of 3 times.

_
    },
);

our %attr_jitter_factor = (
    jitter_factor => {
        summary => 'How much to add randomness',
        schema => ['float*', between=>[0, 0.5]],
        description => <<'_',

If you set this to a value larger than 0, the actual delay will be between a
random number between original_delay * (1-jitter_factor) and original_delay *
(1+jitter_factor). Jitters are usually added to avoid so-called "thundering
herd" problem.

_
    },
);

our %attr_delay_on_failure = (
    delay_on_failure => {
        summary => 'Number of seconds to wait after a failure',
        schema => 'ufloat*',
        req => 1,
    },
);

our %attr_delay_on_success = (
    delay_on_success => {
        summary => 'Number of seconds to wait after a success',
        schema => 'ufloat*',
        default => 0,
    },
);

our %attr_max_delay = (
    max_delay => {
        summary => 'Maximum delay time, in seconds',
        schema => 'ufloat*',
    },
);

$SPEC{new} = {
    v => 1.1,
    is_class_meth => 1,
    is_func => 0,
    args => {
        %attr_max_attempts,
        %attr_jitter_factor,
    },
    result_naked => 1,
    result => {
        schema => 'obj*',
    },
};
sub new {
    my ($class, %args) = @_;

    my $attrspec = ${"$class\::SPEC"}{new}{args};

    # check known attributes
    for my $arg (keys %args) {
        $attrspec->{$arg} or die "$class: Unknown attribute '$arg'";
    }
    # check required attributes and set default
    for my $attr (keys %$attrspec) {
        if ($attrspec->{$attr}{req}) {
            exists($args{$attr})
                or die "$class: Missing required attribute '$attr'";
        }
        if (exists $attrspec->{$attr}{default}) {
            $args{$attr} //= $attrspec->{$attr}{default};
        }
    }
    $args{_attempts} = 0;
    bless \%args, $class;
}

sub _success_or_failure {
    my ($self, $is_success, $timestamp) = @_;
    $timestamp //= time();
    $self->{_last_timestamp} //= $timestamp;
    $timestamp >= $self->{_last_timestamp} or
        die ref($self).": Decreasing timestamp ".
        "($self->{_last_timestamp} -> $timestamp)";
    my $res = $is_success ?
        $self->_success($timestamp) : $self->_failure($timestamp);
    $res = $self->{max_delay}
        if defined $self->{max_delay} && $res > $self->{max_delay};
    $res;
}

sub success {
    my ($self, $timestamp) = @_;

    $self->{_attempts} = 0;

    my $res0 = $self->_success_or_failure(1, $timestamp);
    $res0 -= ($timestamp - $self->{_last_timestamp});
    $self->{_last_timestamp} = $timestamp;
    return 0 if $res0 < 0;
    $self->_add_jitter($res0);
}

sub failure {
    my ($self, $timestamp) = @_;

    $self->{_attempts}++;
    return -1 if $self->{max_attempts} &&
        $self->{_attempts} >= $self->{max_attempts};

    my $res0 = $self->_success_or_failure(0, $timestamp);
    $res0 -= ($timestamp - $self->{_last_timestamp});
    $self->{_last_timestamp} = $timestamp;
    return 0 if $res0 < 0;
    $self->_add_jitter($res0);
}

sub _add_jitter {
    my ($self, $delay) = @_;
    return $delay unless $delay && $self->{jitter_factor};
    my $min = $delay * (1-$self->{jitter_factor});
    my $max = $delay * (1+$self->{jitter_factor});
    $min + ($max-$min)*rand();
}

1;
#ABSTRACT: Various retry/backoff strategies

=head1 SYNOPSIS

 # 1. pick a strategy and instantiate

 use Algorithm::Retry::Constant;
 my $ar = Algorithm::Retry::Constant->new(
     delay_on_failure  => 2, # required
     #delay_on_success => 0, # optional, default 0
 );

 # 2. log success/failure and get a new number of seconds to delay, timestamp is
 # optional but must be monotonically increasing.

 my $secs = $ar->failure(1554652553); # => 2
 my $secs = $ar->success();           # => 0
 my $secs = $ar->failure();           # => 2


=head1 DESCRIPTION

This distribution provides several classes that implement various retry/backoff
strategies.

This class (C<Algorithm::Retry>) is a base class only.


=head1 append:METHODS

=head2 success

Usage:

 my $secs = $obj->success([ $timestamp ]);

Log a successful attempt. If not specified, C<$timestamp> defaults to current
time. Will return the suggested number of seconds to wait before doing another
attempt.

=head2 failure

Usage:

 my $secs = $obj->failure([ $timestamp ]);

Log a failed attempt. If not specified, C<$timestamp> defaults to current time.
Will return the suggested number of seconds to wait before doing another
attempt, or -1 if it suggests that one gives up (e.g. if C<max_attempts>
parameter has been exceeded).


=head1 SEE ALSO

=cut
