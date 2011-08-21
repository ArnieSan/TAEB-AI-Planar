#!/usr/bin/env perl
package TAEB::AI::Planar::Plan::ScareMonster;
use TAEB::OO;
use Moose;
extends 'TAEB::AI::Planar::Plan::Strategic';

has (turntried => (
    isa => 'Maybe[Int]',
    is  => 'rw',
));
has (timesinrow => (
    isa     => 'Int',
    is      => 'rw',
    default => 0
));

# We take a monster as argument.
has (monster => (
    isa     => 'Maybe[TAEB::World::Monster]',
    is  => 'rw',
    default => undef,
));
sub set_arg {
    my $self = shift;
    $self->monster(shift);
}

sub aim_tile {
    my $self = shift;
    my $monster = $self->monster;

    return unless $monster->respects_elbereth;
    return if TAEB->ai->monster_is_peaceful($monster);
    return if defined $monster->spoiler && $monster->spoiler->speed == 0;

    return $monster->tile;
}
sub stop_early { 1 }
sub mobile_target { 1 }
# Whack it!
sub has_reach_action { 1 }
sub reach_action {
    my $self = shift;
    my $ai = TAEB->ai;
    $self->turntried(TAEB->turn);
    # We can build up to meleeing the monster while we're scaring it,
    # so keep stacking Elbereths in case it doesn't move.
    if (TAEB->current_tile->elbereths >= 5) {
        return TAEB::Action->new_action('search', iterations => 1);
    }
    return TAEB::Action->new_action('engrave');
}

sub spread_desirability {
    my $self = shift;
    $self->depends(1,"PardonMe",$self->monster);
}

sub calculate_extra_risk {
    my $self = shift;

    # The time this takes us depends on the speed of the monster. Also,
    # one extra turn for the time it takes to walk.
    my $spoiler = $self->monster->spoiler;
    my $risk = $self->aim_tile_turns(TAEB->speed/($spoiler?$spoiler->speed:12)/0.72+1);

    # If we're continuing with the same plan (i.e. this plan is
    # potentially abandonable), then the cost goes up over time.
    # (This is a compromise between marking it as impossible and
    # repeating indefinitely.)
    my $ap = TAEB->ai->abandoned_plan;
    if (defined $ap && $ap->name eq $self->name) {
        my $tir = $self->timesinrow;
        my $speed = defined $spoiler ? $spoiler->speed : 12;
        my $penalty = $speed/TAEB->speed*$tir;
        $risk += $self->cost("Time", $penalty);
        $self->timesinrow($tir+1);
        TAEB->log->ai("Adding penalty cost $penalty to ScareMonster");
        $penalty > 4 and $self->mark_impossible;
    } else {$self->timesinrow(0);}
    return $risk;
}

sub invalidate { shift->validity(0); }

sub succeeded {
    my $self = shift;
    # It succeeded if the monster is no longer in the way.
    ($self->validity(0), return 1)
        if !defined $self->monster->tile->monster;
    # If the attempt consumed no time, we're in a form that can't engrave.
    $self->turntried == TAEB->turn and return 0;
    return undef; # try again; TODO: Figure out when this won't work
}

use constant description => 'Scaring a monster out of our way';
use constant references => ['PardonMe'];

__PACKAGE__->meta->make_immutable;
no Moose;

1;
