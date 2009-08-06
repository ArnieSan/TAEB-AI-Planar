#!/usr/bin/env perl
package TAEB::AI::Planar::Plan::Extricate;
use TAEB::OO;
use TAEB::Util qw/delta2vi/;
extends 'TAEB::AI::Planar::Plan::Strategic';

# A slightly unusual use of Strategic; here, we're always on the
# aim_tile, so the pathing isn't involved, just the reach action. It's
# done like this so that aim_tile_turns works. (Hmm... maybe all plans
# should be Strategic-based, in that case?)
sub aim_tile {
    return TAEB->current_tile;
}
sub has_reach_action { 1 }

has last_movement_turn => (
    isa => 'Int',
    is  => 'rw',
    default => -1,
);
has consecutive_tries => (
    isa => 'Int',
    is  => 'rw',
    default => 0,
);

# Move diagonally into a wall, if we can.
# Otherwise, move adjacently to an arbitrary passable square.
# Failing even that, bail.
sub reach_action {
    my $self = shift;
    my $ai = TAEB->ai;
    if($self->last_movement_turn == TAEB->turn) {
	$self->consecutive_tries($self->consecutive_tries + 1);
    } else {
	$self->last_movement_turn(TAEB->turn);
	$self->consecutive_tries(0)
    }
    my $goto = undef;
    TAEB->current_tile->each_diagonal(sub {
	my $tile = shift;
	$tile->type eq 'wall' || $tile->type eq 'rock'
	    and $goto = $tile;
    });
    $goto and return TAEB::Action->new_action(
	'move', direction => delta2vi($goto->x - TAEB->x,
				      $goto->y - TAEB->y));
    TAEB->current_tile->each_adjacent(sub {
	my $tile = shift;
	$ai->tile_walkable($tile) && !$tile->monster and $goto = $tile;
    });
    $goto and return TAEB::Action->new_action(
	'move', direction => delta2vi($goto->x - TAEB->x,
				      $goto->y - TAEB->y));
    return undef;
}

sub reach_action_succeeded {
    # This is an interesting one; although it's impossible to tell if
    # we're in a bear-trap or not just from senses, it /is/ possible
    # with knowledge of what the AI is doing. If we moved diagonally
    # into a wall three times in a row and the turn counter didn't go
    # up, we must have escaped from the bear-trap. So we can tell the
    # framework we're no longer entrapped.
    my $self = shift;
    if($self->consecutive_tries >= 3 &&
       $self->last_movement_turn == TAEB->turn) {
	TAEB->in_beartrap(0);
    }
    # If we're still in a trap, return undef, to continue the
    # extrication next turn.
    TAEB->in_beartrap and return undef;
    TAEB->in_web and return undef;
    TAEB->in_pit and return undef;
    return 1; # we're free!
}

# The length of time it takes us to escape.
sub calculate_extra_risk {
    my $self = shift;
    my $trapturns = 0;
    TAEB->in_beartrap and $trapturns = 7;
    TAEB->in_pit and $trapturns = 10;
    TAEB->in_web and $trapturns = 1;
    return $self->aim_tile_turns($trapturns);
}

use constant description => 'Escaping a trap';

__PACKAGE__->meta->make_immutable;
no Moose;

1;
