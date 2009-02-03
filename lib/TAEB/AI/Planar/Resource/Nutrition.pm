#!/usr/bin/env perl
package TAEB::AI::Planar::Resource::Nutrition;
use TAEB::OO;
extends 'TAEB::AI::Planar::Resource';

has _value => (
    isa => 'Num',
    default => 0.01, # 1 point of nutrition is not worth a lot
);

sub amount {
    return TAEB->nutrition;
}

# Scarcity of nutrition reflects which hunger band we're in; low
# nutrition gets more and more urgent the more hungry we are.
sub scarcity {
    my $self = shift;
    my $quantity = shift;
    ($quantity > 1000) and return 0; # only eat if useful
    ($quantity > 150)  and return 1;
    ($quantity > 50)   and return 3;
    ($quantity > 0)    and return 10;
    return 100; # fainting, we need nutrition really badly
}

__PACKAGE__->meta->make_immutable;
no Moose;

1;
