#!/usr/bin/env perl
package TAEB::AI::Plan::Walk;
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
    # We want to favour pathing orthogonally first then diagonally.
    # There are several reasons for this: it saves time in zigzag
    # corridors, it looks nicer, and in theory it's easier to optimise
    # paths if they're consistent between turns (although the AI
    # doesn't take advantage of that at the moment). The gain is 1
    # millinutrition, divided by the number of turns already recorded
    # in the TME (i.e. small enough to make no difference except as a
    # tiebreak) plus one (to avoid division by zero).
    $self->cost("Nutrition",0.001/(($tme->{'risk'}->{'Nutrition'} || 0)+1))
	unless $tile->x == $tme->{'tile_x'} || $tile->y == $tme->{'tile_y'};
}

sub check_possibility_inner {
    my $self = shift;
    my $tme  = shift;
    my $tile = $self->tile;
    return unless $tile->is_walkable;
    if (defined $tile->monster) {
	# We need to generate a plan to scare the monster out of the
	# way, if the AI doesn't want to kill it for some reason.
	$self->generate_plan($tme,"ScareMonster",$tile);
	return;
    }
    $self->add_possible_move($tme,$tile->x,$tile->y,$tile->level);
}

sub action {
    my $self = shift;
    my $tile = $self->tile;
    my $dir = delta2vi($tile->x - TAEB->x, $tile->y - TAEB->y);
    if (!defined $dir) {
	die "Could not move from ".TAEB->x.", ".TAEB->y." to ".
	    $tile->x.", ".$tile->y." because they aren't adjacent.";
    }
    return TAEB::Action->new_action(
	'move', direction => $dir);
}

sub succeeded {
    my $self = shift;
    return TAEB->current_tile == $self->tile;
}

use constant description => 'Walking';

__PACKAGE__->meta->make_immutable;
no Moose;

1;
