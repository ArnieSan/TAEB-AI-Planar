#!/usr/bin/env perl
package TAEB::AI::Planar::Resource::Time;
use TAEB::OO;
use Moose;
extends 'TAEB::AI::Planar::Resource';

# Generally speaking, we don't run short of time, it's not a resource
# that can be run out of unless we're aiming for a new world record.
sub amount {
    return 1e6;
}

# The value of time is calculated a bit oddly. The cost of 1 turn is
# equal to the cost of 1 nutrition (increased if things cause us
# hunger). So we're less likely to dawdle when we have hunger we can't
# fix. (Ideally this should reflect other things than nutrition, but
# nutrition is a decent approximiation for now.) Time is still valuable
# even if nutrition is worthless, though.
sub value {
    my $self = shift;
    my $nutrition = TAEB->ai->resources->{'Nutrition'};
    return $nutrition->value || 0.01;
}

# The cost of an amount of time (as opposed to its risk) is the cost
# of the nutrition that will be used up during that amount of time.
# Again, allowing for a minimum value.
sub cost {
    my $self = shift;
    my $quantity = shift;
    my $nutrition = TAEB->ai->resources->{'Nutrition'};
    return $nutrition->cost($quantity) || 0.01 * $quantity;
}

# If people like spending time a lot, nutrition becomes more valuable
# as a result.
sub want_to_spend {
    my $self = shift;
    my $quantity = shift;
    my $nutrition = TAEB->ai->resources->{'Nutrition'};
    $nutrition->want_to_spend($quantity);
}

__PACKAGE__->meta->make_immutable;
no Moose;

1;
