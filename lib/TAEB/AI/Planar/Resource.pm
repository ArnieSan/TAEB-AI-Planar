#!/usr/bin/env perl
package TAEB::AI::Planar::Resource;
use TAEB::OO;

has _value => (
    isa => 'Num',
    default => 1.0,
);
sub base_value {
    return shift->_value;
}

# Give the value of this resource at the moment. Normally that will
# just be _value*scarcity, but for some things, like time, it's weird.
sub value {
    my $self = shift;
    return $self->_value * $self->scarcity($self->amount);
}

# Calculate the cost of a certain amount of this resource.
sub cost {
    my $self = shift;
    my $quantity = shift;
    my $cost = $self->_value * $quantity *
	$self->scarcity($self->amount-$quantity);
    return $cost;
}

# We want to spend this resource, make it more valuable.
# TODO: Make the amount depend on the quantity we want to spend.
# This should be called either by an AI which wants to spend the
# resource but can't, or by the AI when it's about to spend the
# resource, to let us know it's in demand.
sub want_to_spend {
    my $self = shift;
    my $quantity = shift;
    my $value = $self->_value;
    for my $resource (values %{TAEB->ai->resources}) {
	$resource == $self and next;
	$value += $resource->degrade;
    }
    $self->_value($value);
}

# Another resource queried cost, degrade the value of this one
# slightly. Return the amount of value that was lost.
sub degrade {
    return 0; # Doing nothing is probably better than doing this
    my $self = shift;
    my $value = $self->_value;
    $value *= 0.99;
    $self->_value($value);
    return $value/99.0;
}

# Determine how much of this resource we have at the moment, by
# querying the framework.
sub amount {
    die 'Please overload amount in Resource...';
}

# The multiplier on value for this resource according to how scarce it
# currently is. The argument is the quantity of the resource to assume
# when calculating scarcity.
sub scarcity {
    return 1;
}

__PACKAGE__->meta->make_immutable;
no Moose;

1;

