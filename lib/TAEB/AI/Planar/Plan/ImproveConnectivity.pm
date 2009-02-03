#!/usr/bin/env perl
package TAEB::AI::Planar::Plan::ImproveConnectivity;
use TAEB::OO;
use TAEB::Util qw/vi2delta/;
extends 'TAEB::AI::Planar::Plan';

# Returns true if this tile is blocked for the purpose of searching.
# Tiles are searchable if they have exactly 3 blocked orthogonal
# neighbours.
sub is_search_blocked {
    my $self = shift;
    my $tile = shift;
    return (($tile->type eq 'rock' || $tile->type eq 'wall') &&
	    !$tile->has_boulder);
}

sub spread_desirability {
    my $self = shift;
    my $level = TAEB->current_level;
    my $mines = $level->known_branch && $level->branch eq 'mines';
    $level->each_tile(sub {
	my $tile = shift;
	if(!$mines && $tile->is_walkable(0) &&
	   scalar $tile->grep_orthogonal(
	       sub {$self->is_search_blocked(shift)}) == 3) {
	    $self->depends(1,"Search",$tile);
	}
	# It makes sense to explore tiles we haven't explored yet as
	# one of the main ways to improve connectivity. Don't try to
	# explore tiles with unknown pathability, or which are rock,
	# though; that just wastes time in the strategy analyser for
	# an option which is never the correct one. As an exception to
	# this, we /do/ try to explore unexplored tiles when blind, so
	# that LightTheWay kicks in and attempts to route there.
	if(!$tile->explored &&
	   ($tile->type !~ /^(?:rock|unexplored)$/o ||
	    TAEB->is_blind)) {
	    $self->depends(1,"Explore",$tile);
	}
    });
}

use constant description => 'Improving connectivity on this level';

__PACKAGE__->meta->make_immutable;
no Moose;

1;
