#!/usr/bin/env perl
package TAEB::AI::Planar::Plan::LightTheWay;
use TAEB::OO;
use TAEB::Util qw/delta2vi/;
extends 'TAEB::AI::Planar::Plan::Tactical';

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
    # Searching takes 1 turn. Then stepping onto the tile takes
    # another turn.
    $self->cost("Time",2);
    $self->level_step_danger($self->tile->level);
}

sub check_possibility_inner {
    my $self = shift;
    my $tme  = shift;
    my $tile = $self->tile;
    return unless $tile->type eq 'unexplored';
    $self->add_possible_move($tme,$tile->x,$tile->y,$tile->level);
}

sub action {
    my $self = shift;
    return TAEB::Action->new_action('Search', iterations => 1);
}

sub succeeded {
    my $self = shift;
    # It succeeded if we can now see the tile in question.
    ($self->validity(0), return 1) if $self->tile->type ne 'unexplored';
    return 0;
}

use constant description => 'Searching an unexplored tile';

__PACKAGE__->meta->make_immutable;
no Moose;

1;
