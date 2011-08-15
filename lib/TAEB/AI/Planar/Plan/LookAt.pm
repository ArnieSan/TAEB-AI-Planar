#!/usr/bin/env perl
package TAEB::AI::Planar::Plan::LookAt;
use TAEB::OO;
use Moose;
extends 'TAEB::AI::Planar::Plan::Strategic';

has (tile => (
    isa => 'TAEB::World::Tile',
    is  => 'rw',
));
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
    my $tile = $self->tile;
    $self->depends(1,"ExploreLevel",$tile->level);
    # If there's a monster on the tile we want to look at, get rid of
    # it.
    $tile->monster and $self->depends(1,"Eliminate",$tile->monster);
}

use constant description => 'Looking at a tile';
use constant references => ['ExploreLevel'];

__PACKAGE__->meta->make_immutable;
no Moose;

1;
