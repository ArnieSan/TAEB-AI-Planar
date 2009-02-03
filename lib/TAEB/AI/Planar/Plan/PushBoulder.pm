#!/usr/bin/env perl
package TAEB::AI::Plan::PushBoulder;
use TAEB::OO;
use TAEB::Util qw/delta2vi/;
extends 'TAEB::AI::Plan::Tactical';

has tile => (
    isa => 'Maybe[TAEB::World::Tile]',
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
    $self->cost("Time",1);
    $self->level_step_danger($tile->level);
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

use constant description => 'Pushing a boulder';

__PACKAGE__->meta->make_immutable;
no Moose;

1;
