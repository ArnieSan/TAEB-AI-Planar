#!/usr/bin/env perl
package TAEB::AI::Planar::Plan::PushBoulderRisky;
use TAEB::OO;
use TAEB::Util qw/delta2vi/;
extends 'TAEB::AI::Planar::Plan::Tactical';

has tile => (
    isa => 'Maybe[TAEB::World::Tile]',
    is  => 'rw',
    default => undef,
);
sub set_additional_args {
    my $self = shift;
    $self->tile(shift);
}

sub calculate_risk {
    my $self = shift;
    my $tme  = shift;
    my $tile = $self->tile;
    $self->cost("Time",5); # add a large don't-do-this penalty
    $self->level_step_danger($tile->level) for 1..5;
}

sub check_possibility_inner {
    my $self = shift;
    my $tme  = shift;
    my $tile = $self->tile;
    $self->add_possible_move($tme,$tile->x,$tile->y,$tile->level);
}

sub action {
    my $self = shift;
    my $tile = $self->tile;
    return TAEB::Action->new_action(
	'move', direction => delta2vi($tile->x - TAEB->x, $tile->y - TAEB->y));
}

sub succeeded {
    my $self = shift;
    return TAEB->current_tile == $self->tile;
}

use constant description => "Pushing a boulder we don't really want to move";

__PACKAGE__->meta->make_immutable;
no Moose;

1;
