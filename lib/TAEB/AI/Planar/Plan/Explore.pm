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

# Marginally favour pathing to closer squares first, if there's a tie.
# This tends to prevent a need to go back and re-explore locations
# later.
sub calculate_extra_risk {
    my $self = shift;
    my $tct = TAEB->current_tile;
    my $tile = $self->tile;
    $self->cost("Delta",
                ($tct->x-$tile->x)*($tct->x-$tile->x)+
                ($tct->y-$tile->y)*($tct->y-$tile->y));
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
