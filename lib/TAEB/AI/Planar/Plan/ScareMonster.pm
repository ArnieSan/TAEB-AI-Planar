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

has turntried => (
    isa => 'Maybe[Int]',
    is  => 'rw',
);
has timesinrow => (
    isa     => 'Int',
    is      => 'rw',
    default => 0
);

sub calculate_risk {
    my $self = shift;
    # The time this takes us depends on the speed of the monster.
    my $spoiler = $self->tile->monster->spoiler;
    if (defined $spoiler && $spoiler->speed > 0)
    {
	# There's a 72% chance of a valid dust-Elbereth.
	# Remember to add 1 for the time it takes to step onto the tile!
	$self->cost("Time",TAEB->speed/$spoiler->speed/0.72+1);
        # Don't scare a monster when you could walk around it.
        $self->cost("Delta",10);
    } else {
	# Most of the things we want to scare are rather slow...
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
    my $self = shift;
    my $tme  = shift;
    my $tile = $self->tile;
    my $monster = $tile->monster;
    return unless defined $monster;
    # It might be peaceful (shk, watchman...)
    $self->generate_plan($tme,"PardonMe",$tile);
    # We can't scare a monster that doesn't respect Elbereth.
    return unless $monster->respects_elbereth;
    # We can't scare an immobile monster.
    my $spoiler = $monster->spoiler;
    my $timesaved = undef;
    if($spoiler and !($spoiler->speed)) {
        $timesaved = {Impossibility => 1};
    } elsif($spoiler) {
        $timesaved = {Time => TAEB->speed/$spoiler->speed/0.72+1};
    }
    # Eliminating may be faster, even if it's a peaceful.
    if(defined $timesaved) {
        my $ai = TAEB->ai;
        # We need to convert this into a /strategic/ plan, Eliminate.
        # This is done by inventing a threat on the square, and setting
        # its difficulty for routing past to "impossible".
        # TODO: This is rather encapsulation-breaking; maybe there
        # should be a convert-tactics-to-strategy function in the AI
        # somewhere?
        my $planname = $ai->get_plan("Eliminate",$monster)->name;
        $ai->threat_map->{$tile->level}->[$tile->x]->[$tile->y]->{"-1 $planname"}
            = $timesaved;
    }
    $self->add_possible_move($tme,$tile->x,$tile->y,$tile->level);
}

sub action {
    my $self = shift;
    $self->turntried(TAEB->turn);
    return TAEB::Action->new_action('Engrave');
}

sub succeeded {
    my $self = shift;
    # It succeeded if the monster is no longer in the way.
    ($self->validity(0), return 1) if ! defined $self->tile->monster;
    # If the attempt consumed no time, we're in a form that can't engrave.
    $self->turntried == TAEB->turn and return 0;
    return undef; # try again; TODO: Figure out when this won't work
}

use constant description => 'Scaring a monster out of our way';
use constant references => ['PardonMe'];

__PACKAGE__->meta->make_immutable;
no Moose;

1;
