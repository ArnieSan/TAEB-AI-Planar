#!/usr/bin/env perl
package TAEB::AI::Planar::Resource::CarryCapacity;
use TAEB::OO;
extends 'TAEB::AI::Planar::Resource';

has _value => (
    isa => 'Num',
    is  => 'rw',
    default => 0.01, # at the start of the game, encumberance hardly matters
);

sub amount {
    return TAEB->unburdened_limit - TAEB->inventory->weight;
}

# The more we have, the more important it is to save weight.
sub scarcity {
    my $self = shift;
    my $quantity = shift;
    my $ratio = $quantity / TAEB->unburdened_limit;
    ($quantity > 0.5)  and return 1;
    ($quantity > 0.3)  and return 50;
    ($quantity > 0.2)  and return 100;
    ($quantity > 0.15) and return 500;
    ($quantity > 0.1)  and return 1000;
    ($quantity > 0.07) and return 2000;
    ($quantity > 0.05) and return 4000;
    ($quantity > 0.03) and return 6000;
    ($quantity > 0.02) and return 10000;
    ($quantity > 0.01) and return 20000;
    return 30000;
}

__PACKAGE__->meta->make_immutable;
no Moose;

1;
