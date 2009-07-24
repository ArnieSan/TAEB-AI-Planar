#!/usr/bin/env perl
package TAEB::AI::Planar::Plan::ExploreLevel;
use TAEB::OO;
use TAEB::Util qw/vi2delta/;
extends 'TAEB::AI::Planar::Plan';

# We take a level as argument.
has level => (
    isa     => 'Maybe[TAEB::World::Level]',
    is      => 'rw',
    default => undef,
);
sub set_arg {
    my $self = shift;
    my $level = shift;
    $self->level($level);
}

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
    my $level = $self->level;
    my $mines = $level->known_branch && $level->branch eq 'mines'
        && !$level->is_minetown;
    my $blind = TAEB->is_blind;
    $level->each_tile(sub {
	my $tile = shift;
	if($tile->is_walkable(0,1)) {
	   my $orthogonals = scalar $tile->grep_orthogonal(
	       sub {$self->is_search_blocked(shift)});
           # Dead-end; a very good place to search, even when not stuck.
           $orthogonals == 3 and $self->depends($mines ? 0.5 : 1, "Search", $tile);
        }
	# It makes sense to explore tiles we haven't explored yet as
	# one of the main ways to improve connectivity. Don't try to
	# explore tiles with unknown pathability, or which are rock,
	# though; that just wastes time in the strategy analyser for
	# an option which is never the correct one. As an exception to
	# this, we /do/ try to explore unexplored tiles when blind, so
	# that LightTheWay kicks in and attempts to route there.
	
	# Also, we don't want to explore rock or walls, because there's
	# not a lot to see behind them and digging out entire levels takes
	# lots of time.
	if(!$tile->explored &&
	   ($blind || $tile->type !~ /^(?:rock|wall|unexplored)$/o)) {
	    $self->depends(1,"Explore",$tile);
	}
	# As well as exploring horizontally, we can explore vertically.
	# Looking underneath objects is one way to help find the stairs.
        # However, only do this if we've never stepped on the tile; if
        # we've ever stepped on the tile, we know its terrain.
	if($tile->is_interesting && !$tile->stepped_on) {
	    $self->depends(1,"LookAt",$tile);
	}
        if($tile->has_boulder && $tile->type eq 'obscured') {
            $self->depends(1,"LookAt",$tile);
        }
    });
    # If possible, paying off debt can improve connectivity by
    # allowing us to move past a shk. TODO: This should be a threat.
    $self->depends(1,"Pay");
    # Eliminating (not mitigating) invisible monsters can help us
    # explore by opening up more of the level.
    for my $enemy (TAEB->current_level->has_enemies) {
        $enemy->tile->glyph eq 'I'
            and $self->depends(1,"Eliminate",$enemy);
    }
    # Fallbacks for ExploreLevel are in their own plan, to enable
    # the level to fallback-search to be different from the level
    # to be explored.
    $self->depends(0.5,'FallbackExplore',$level);
}

use constant description => 'Exploring a level';
use constant references => ['Search','Explore','Pay','Eliminate',
                            'LookAt','FallbackExplore'];

__PACKAGE__->meta->make_immutable;
no Moose;

1;
