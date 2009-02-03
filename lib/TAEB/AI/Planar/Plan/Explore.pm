#!/usr/bin/env perl
package TAEB::AI::Plan::Explore;
use TAEB::OO;
extends 'TAEB::AI::Plan::PathBased';

has tile => (
    isa => 'TAEB::World::Tile',
);
sub set_arg {
    my $self = shift;
    $self->tile(shift);
}

sub aim_tile {
    return shift->tile;
}

sub invalidate {
    my $self = shift;
    $self->validity(0) if $self->tile->explored;
}

sub spread_desirability {
    # Improving connectivity on the level allows us to explore more
    # squares.
    my $self = shift;
    $self->depends(1,"ImproveConnectivity");
}

use constant description => 'Exploring';

__PACKAGE__->meta->make_immutable;
no Moose;

1;
