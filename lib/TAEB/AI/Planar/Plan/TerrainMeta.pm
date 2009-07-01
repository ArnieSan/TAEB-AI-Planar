#!/usr/bin/env perl
package TAEB::AI::Planar::Plan::TerrainMeta;
use TAEB::OO;
extends 'TAEB::AI::Planar::Plan';

# We take a tile as argument.
has tile => (
    isa     => 'Maybe[TAEB::World::Tile]',
    is      => 'rw',
    default => undef,
);
sub set_arg {
    my $self = shift;
    $self->tile(shift);
}

# note: invalidate does not invalidate this plan, terrain tends to stick
# around

sub planspawn {
    my $self = shift;
    my $tile = $self->tile;
    # If these are stairs with an unknown other side, generate an
    # OtherSide plan.
    if (($tile->type eq 'stairsup' || $tile->type eq 'stairsdown')
        && !defined $tile->other_side) {
        TAEB->ai->get_plan('OtherSide',$tile)->validate;
    }
    # We can dip for Excalibur in fountains.
    if ($tile->type eq 'fountain') {
        TAEB->ai->get_plan('Excalibur',$tile)->validate;
    }
}

use constant description => "Investigating unusual terrain";
use constant references => ['OtherSide','Excalibur'];

__PACKAGE__->meta->make_immutable;
no Moose;

1;
