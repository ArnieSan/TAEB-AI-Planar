#!/usr/bin/env perl
package TAEB::AI::Planar::Resource::DamagePotential;
use TAEB::OO;
use TAEB::Spoilers::Combat;
extends 'TAEB::AI::Planar::Resource';

has _value => (
    isa     => 'Num',
    is      => 'rw',
    default => 40,
);

sub is_lasting { 1 }

sub amount {
    return TAEB::Spoilers::Combat->damage(
        TAEB->inventory->equipment->weapon // '-');
}

# We want all the damage we can get.
sub scarcity { 1 }

__PACKAGE__->meta->make_immutable;
no Moose;

1;
