#!/usr/bin/env perl
package TAEB::AI::Planar::Plan::LookAt;
use TAEB::OO;
extends 'TAEB::AI::Planar::Plan::Strategic';

has tile => (
    isa => 'TAEB::World::Tile',
    is  => 'rw',
);
sub set_arg {
    my $self = shift;
    $self->tile(shift);
}

sub aim_tile {
    return shift->tile;
}

sub spread_desirability {
    # Improving connectivity on the level allows us to more easily
    # reach the square we want to look at. TODO: directed explore?
    my $self = shift;
    $self->depends(1,"ExploreLevel",$self->tile->level);
}

use constant description => 'Looking at a tile';
use constant references => ['ExploreLevel'];

__PACKAGE__->meta->make_immutable;
no Moose;

1;
