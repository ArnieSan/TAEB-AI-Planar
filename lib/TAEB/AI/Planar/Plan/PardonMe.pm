#!/usr/bin/env perl
package TAEB::AI::Planar::Plan::PardonMe;
use TAEB::OO;
use TAEB::Util qw/delta2vi/;
extends 'TAEB::AI::Planar::Plan::Tactical';

has timesinrow => (
    isa     => 'Int',
    is      => 'rw',
    default => 0
);

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
    # The time this takes us depends on the speed of the monster. Also,
    # one extra turn for the time it takes to walk.
    my $spoiler = $self->tile->monster->spoiler;
    if (defined $spoiler && $spoiler->speed > 0)
    {
	$self->cost("Time",TAEB->speed/$spoiler->speed+1);
    } else {
	# an estimate
	$self->cost("Time",10);
    }
    # If we're continuing with the same plan (i.e. this plan is
    # potentially abandonable), then the cost goes up over time.
    # (This is a compromise between marking it as impossible and
    # repeating indefinitely.)
    my $ap = TAEB->ai->abandoned_tactical_plan;
    if (defined $ap && $ap->name eq $self->name) {
        my $tir = $self->timesinrow;
        my $speed = defined $spoiler ? $spoiler->speed : 12;
        my $penalty = $speed/TAEB->speed*$tir;
        $self->cost("Time", $penalty);
        $self->timesinrow($tir+1);
        TAEB->log->ai("Adding penalty cost $penalty to PardonMe");
        $penalty > 4 and $self->mark_impossible;
    } else {$self->timesinrow(0);}
    $self->level_step_danger($self->tile->level);
}

sub check_possibility_inner {
    my $self    = shift;
    my $tme     = shift;
    my $ai      = TAEB->ai;
    my $tile    = $self->tile;
    my $monster = $tile->monster;
    return unless defined $monster;
    # We can only wait for peaceful monsters to move out of the way.
    return unless $ai->monster_is_peaceful($monster);
    # We can't wait for an immobile monster.
    my $spoiler = $tile->monster->spoiler;
    return if $spoiler and !($spoiler->speed);
    $self->add_possible_move($tme,$tile->x,$tile->y,$tile->level);
}

sub action {
    my $self = shift;
    return TAEB::Action->new_action('Search', iterations => 1);
}

sub succeeded {
    my $self = shift;
    # It succeeded if the monster is no longer in the way.
    ($self->validity(0), return 1) if ! defined $self->tile->monster;
    return undef; # try again; TODO: Figure out when this won't work
}

use constant description => 'Waiting for a monster to move';

__PACKAGE__->meta->make_immutable;
no Moose;

1;
