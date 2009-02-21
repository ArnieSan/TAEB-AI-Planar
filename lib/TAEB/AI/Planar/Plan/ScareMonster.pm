#!/usr/bin/env perl
package TAEB::AI::Planar::Plan::ScareMonster;
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
    # The time this takes us depends on the speed of the monster.
    my $spoiler = $self->tile->monster->spoiler;
    if (defined $spoiler)
    {
	# There's a 72% chance of a valid dust-Elbereth.
	# Remember to add 1 for the time it takes to step onto the tile!
	$self->cost("Time",TAEB->speed/$spoiler->{'speed'}/0.72+1);
    } else {
	# Most of the things we want to scare are rather slow...
	$self->cost("Time",10);
    }
    $self->level_step_danger($self->tile->level);
}

sub check_possibility_inner {
    my $self = shift;
    my $tme  = shift;
    my $tile = $self->tile;
    my $monster = $tile->monster;
    return unless defined $monster;
    # We can't scare a monster that doesn't respect Elbereth.
    unless ($monster->respects_elbereth) {
	# It might be peaceful (shk, watchman...)
	$self->generate_plan($tme,"PardonMe",$tile);
	return;
    }
    # We can't scare an immobile monster.
    my $spoiler = $tile->monster->spoiler;
    return if $spoiler and !($spoiler->{'speed'});
    $self->add_possible_move($tme,$tile->x,$tile->y,$tile->level);
}

sub action {
    my $self = shift;
    return TAEB::Action->new_action('Engrave');
}

sub succeeded {
    my $self = shift;
    # It succeeded if the monster is no longer in the way.
    ($self->validity(0), return 1) if ! defined $self->tile->monster;
    return undef; # try again; TODO: Figure out when this won't work
}

use constant description => 'Scaring a monster out of our way';
use constant references => ['PardonMe'];

__PACKAGE__->meta->make_immutable;
no Moose;

1;
