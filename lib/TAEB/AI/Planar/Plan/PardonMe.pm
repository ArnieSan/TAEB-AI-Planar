#!/usr/bin/env perl
package TAEB::AI::Planar::Plan::PardonMe;
use TAEB::OO;
use TAEB::Util qw/delta2vi/;
use Moose;
extends 'TAEB::AI::Planar::Plan::DirectionalTactic';
with 'TAEB::AI::Planar::Meta::Role::SqueezeChecked';

has (timesinrow => (
    isa     => 'Int',
    is      => 'rw',
    default => 0
));

sub calculate_risk {
    my $self = shift;
    my $tme  = shift;
    # The time this takes us depends on the speed of the monster. Also,
    # one extra turn for the time it takes to walk.
    my $spoiler = $self->tile($tme)->monster->spoiler;
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
    $self->level_step_danger($self->tile($tme)->level);
}

sub check_possibility {
    my $self    = shift;
    my $tme     = shift;
    my $ai      = TAEB->ai;
    my $tile    = $self->tile($tme);
    my $monster = $tile->monster;
#    TAEB->log->ai("Considering to ask $monster off $tile");
    return unless defined $monster;
    # We can only wait for peaceful monsters to move out of the way.
    return unless $ai->monster_is_peaceful($monster);
    # We can't wait for an immobile monster.
    my $spoiler = $tile->monster->spoiler;
    return if $spoiler and !($spoiler->speed);
#    TAEB->log->ai("It might work");
    $self->add_directional_move($tme);
}

sub action {
    my $self = shift;
    my $ai = TAEB->ai;
    TAEB->log->ai("Trying to ask off a tile");
    TAEB->known_debt or TAEB->send_message(check => 'debt');
    TAEB->debt and return TAEB::Action->new_action('pay', item => 'all');
    # If it's a shopkeeper we're trying to avoid, try moving so as to
    # be adjacent to both the shk and where we're aiming; shks tend
    # not to move if we don't. TODO: Allow for threats in this. Maybe
    # this should be fallback-to-strategic?
    if ($self->tile->monster->is_shk &&
        TAEB->current_tile->type ne 'opendoor') {
        return TAEB::Action->new_action(
            'move', direction => delta2vi($_->x - TAEB->x, $_->y - TAEB->y))
            for $self->tile->grep_adjacent(sub {
                my $t = shift;
                $ai->tile_walkable($t) &&
                    !$t->monster &&
                    $t->type ne 'opendoor' &&
                    abs(TAEB->x - $t->x <= 1) &&
                    abs(TAEB->y - $t->y <= 1);
            });
    }
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
