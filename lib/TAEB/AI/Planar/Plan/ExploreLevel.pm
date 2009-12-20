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

sub spread_desirability {
    my $self = shift;
    my $level = $self->level;
    my $mines = $level->known_branch && $level->branch eq 'mines'
        && !$level->is_minetown;
    my $blind = TAEB->is_blind;
    my $ai = TAEB->ai;

    # It makes sense to explore tiles we haven't explored yet as
    # one of the main ways to improve connectivity. Don't try to
    # explore tiles with unknown pathability, or which are rock,
    # though; that just wastes time in the strategy analyser for
    # an option which is never the correct one. As an exception to
    # this, we /do/ try to explore unexplored tiles when blind, so
    # that LightTheWay kicks in and attempts to route there.

    # Work out a cached exploration graph.
    my $cache = $ai->plan_caches->{'ExploreLevel'};
    $cache or $ai->plan_caches->{'ExploreLevel'} = $cache = {};
    # We're only going to have new info to cache about the current level.
    if ($level == TAEB->current_level || !$cache->{$level}) {
        my $iterator = 'each_tile';
        my $TAEBstep = TAEB->step;
        $iterator = 'each_changed_tile_and_neighbors'
            if $cache->{'_lastlevel'} && $cache->{'_lastlevel'} == $level
            && ($cache->{'_laststep'} // -2) + 1 == $TAEBstep;
        $cache->{'_lastlevel'} = $level;
        $cache->{'_laststep'} = $TAEBstep;
        $cache->{$level} = 1; # a cache for this level's been created
        TAEB->log->ai("ExploreLevel with iterator $iterator.");
        $level->$iterator(sub {
            my $tile = shift;
            # Yes, the cached value is also cached...
            my $tilecache = ($cache->{$tile} //= 0);
            my $explored  = $tile->explored;
            my $tiletype  = $tile->type;

            # Don't explore rock or walls; explore 'unexplored' tiles only
            # if they're adjacent to an explored, walkable tile. This
            # needs caching to work quickly:
            # cache =  0: no information stored
            # cache =  1: unexplored, !explored, and adjacent to
            #             an explored tile or known-walkable tile
            # cache =  2: !explored and not rock/wall/unexplored
            # cache =  3: !explored walkable
            # cache = -1: rock or wall
            # cache = -2: explored, not rock or wall, and might be a dead end
            # cache = -3: explored, not rock or wall, and not a dead end
            # Whenever a tile becomes explored, the cache value of all
            # adjacent unexplored and !explored tiles becomes 1; this is
            # the only way a tile's cache value can become 1.
            if ($tiletype =~ /^(?:rock|wall)$/o && !$tile->has_boulder) {
                $cache->{$tile} = -1;
            } elsif ($tilecache > -1 && $explored) {
                $cache->{$tile} = -2;
                $tile->each_adjacent(sub {
                    my $x = shift;
                    $x->type eq 'unexplored' and $cache->{$x} = 1;
                });
            } elsif ($tilecache < 3 && !$explored && $ai->tile_walkable($tile)) {
                $cache->{$tile} = 3;
                $tile->each_adjacent(sub {
                    my $x = shift;
                    $x->type eq 'unexplored' and $cache->{$x} = 1;
                });
            } elsif (!$tilecache && $tiletype ne 'unexplored') {
                $cache->{$tile} = 2;
            }
        });
    }
    if($self->useful_to_depend(1, $level)) {
        $level->each_tile(sub {
            my $tile = shift;
            my $tilecache = $cache->{$tile};
            
            # Search dead-end corridors and doorways, if we've explored the
            # square to search from first.
            if($tilecache == -2) {
                my $orthogonals = scalar ($tile->grep_orthogonal(
                                              sub {$cache->{(shift)} == -1}));
                # Dead-end; a very good place to search, even when not stuck.
                if($orthogonals == 3) {
                    $self->depends($mines ? 0.5 : 1, "Search", $tile);
                } else {
                    # If this tile is explored, but not currently a dead end,
                    # it never will be. So mark this tile as 'not a dead end'.
                    $cache->{$tile} = -3;
                }
            }
            
            # Use the cached values for exploration.
            if ($tilecache > 0) {
                $self->depends(1,"Explore",$tile);
            }
            # As well as exploring horizontally, we can explore vertically.
            # Looking underneath objects is one way to help find the stairs.
            # However, only do this if we've never stepped on the tile; if
            # we've ever stepped on the tile, we know its terrain.
            if($tile->is_interesting && !$tile->stepped_on) {
                $self->depends(1,"LookAt",$tile);
            } elsif($tile->type eq 'obscured' && $tile->has_boulder) {
                $self->depends(1,"LookAt",$tile);
            }
        });
    } else {
        TAEB->log->ai("Not exploring $level, there's definitely a better plan");
    }
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
