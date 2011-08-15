#!/usr/bin/env perl
package TAEB::AI::Planar::Plan::PardonMe;
use TAEB::OO;
use TAEB::Util qw/delta2vi/;
use Moose;
use TAEB::AI::Planar::Plan::Tunnel;
extends 'TAEB::AI::Planar::Plan::Strategic';

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

    # Hostiles won't move of their own accord.
    return unless TAEB->ai->monster_is_peaceful($monster);

    # Shopkeepers won't move if we have a pickaxe or mattock.
    if ($monster->is_shk) {
        my ($p) =
            TAEB::AI::Planar::Plan::Tunnel->get_pick_and_time;
        return  if $p;
    }

    return $monster->tile;
}
sub stop_early { 1 }
sub mobile_target { 1 }
# Whack it!
sub has_reach_action { 1 }
sub reach_action {
    my $self = shift;
    my $ai = TAEB->ai;
    my $monster = $self->monster;
    TAEB->known_debt or TAEB->send_message(check => 'debt');
    TAEB->debt and return TAEB::Action->new_action('pay', item => 'all');
    # If it's a shopkeeper we're trying to avoid, try moving so as to
    # be adjacent to both the shk and where we're aiming; shks tend
    # not to move if we don't.
    if ($monster->is_shk &&
        TAEB->current_tile->type ne 'opendoor') {
        return TAEB::Action->new_action(
            'move', direction => delta2vi($_->x - TAEB->x, $_->y - TAEB->y))
            for $monster->tile->grep_adjacent(sub {
                my $t = shift;
                $ai->tile_walkable($t) &&
                    !$t->monster &&
                    $t->type ne 'opendoor' &&
                    abs(TAEB->x - $t->x <= 1) &&
                    abs(TAEB->y - $t->y <= 1);
            });
    }
    return TAEB::Action->new_action('search', iterations => 1);
}

sub calculate_extra_risk {
    my $self = shift;
    # The time this takes us depends on the speed of the monster. Also,
    # one extra turn for the time it takes to walk.
    my $spoiler = $self->monster->spoiler;
    my $risk;
    if (defined $spoiler && $spoiler->speed > 0)
    {
	$risk = $self->aim_tile_turns(TAEB->speed/$spoiler->speed+1);
    } else {
	# an estimate
	$risk = $self->aim_tile_turns(10);
    }
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
        TAEB->log->ai("Adding penalty cost $penalty to PardonMe");
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

    return undef; # try again; TODO: Figure out when this won't work
}

use constant description => 'Waiting for a monster to move';

__PACKAGE__->meta->make_immutable;
no Moose;

1;
