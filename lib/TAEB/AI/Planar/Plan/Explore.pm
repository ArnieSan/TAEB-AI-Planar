#!/usr/bin/env perl
package TAEB::AI::Planar::Plan::Explore;
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

sub invalidate {
    my $self = shift;
    $self->validity(0) if $self->tile->explored;
}

use constant description => 'Exploring';

__PACKAGE__->meta->make_immutable;
no Moose;

1;
