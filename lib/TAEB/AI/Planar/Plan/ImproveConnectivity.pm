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
    my $mines = $level->known_branch && $level->branch eq 'mines'
        && !$level->is_minetown;
    my $blind = TAEB->is_blind;
    $level->each_tile(sub {
	my $tile = shift;
	if($tile->is_walkable(0,1)) {
	   my $orthogonals = scalar $tile->grep_orthogonal(
	       sub {$self->is_search_blocked(shift)});
           # Dead-end; a very good place to search, even when not stuck
           $orthogonals == 3 and $self->depends($mines ? 0.5 : 1, "Search", $tile);
           # If there's even one tile, this place can be used for fallback
           # search.
           ($orthogonals == 1 || $orthogonals == 2) and
               $self->depends($mines ? 0.3 : 0.5, "Search", $tile);
        }
	# It makes sense to explore tiles we haven't explored yet as
	# one of the main ways to improve connectivity. Don't try to
	# explore tiles with unknown pathability, or which are rock,
	# though; that just wastes time in the strategy analyser for
	# an option which is never the correct one. As an exception to
	# this, we /do/ try to explore unexplored tiles when blind, so
	# that LightTheWay kicks in and attempts to route there.
	if(!$tile->explored &&
	   ($blind || $tile->type !~ /^(?:rock|unexplored)$/o)) {
	    $self->depends(1,"Explore",$tile);
	}
	# As well as exploring horizontally, we can explore vertically.
	# Looking underneath objects is one way to help find the stairs.
	if($tile->is_interesting) {
	    $self->depends(1,"Explore",$tile);
	}
    });
    # If possible, paying off debt can improve connectivity by
    # allowing us to move past a shk.
    $self->depends(1,"Pay");
}

use constant description => 'Improving connectivity on this level';
use constant references => ['Search','Explore','Pay'];

__PACKAGE__->meta->make_immutable;
no Moose;

1;
