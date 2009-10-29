#!/usr/bin/env perl
package TAEB::AI::Planar::Plan::FallbackExplore;
use TAEB::AI::Planar::Plan::ExploreLevel;
use TAEB::OO;
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
    return ($tile->type eq 'rock' || $tile->type eq 'wall')
        && !$tile->has_boulder;
}

sub spread_desirability {
    my $self = shift;
    my $level = $self->level;
    my $mines = $level->known_branch && $level->branch eq 'mines'
        && !$level->is_minetown;
    my $blind = TAEB->is_blind;
    my $ai = TAEB->ai;
    $level->each_tile(sub {
	my $tile = shift;
	if($ai->tile_walkable($tile)) {
	   my $orthogonals = scalar $tile->grep_orthogonal(
	       sub {$self->is_search_blocked(shift)});
           ($orthogonals == 1 || $orthogonals == 2) and
               $self->depends($mines ? 0.7 : 1, "Search", $tile);
        }
    });
    $self->depends(0.8, "ExploreViaTeleport");
    # if we're even considering this, also recheck stairs after the
    # next action. TODO: I don't get why this is necessary; when we
    # discover why it is, presumably a less hacky version can be
    # used
    my %stairplans = $ai->plan_index_by_type("Stairs");
    for my $plan (values %stairplans) {
        $plan->required_success_count(0);
    }
}

use constant description => 'Exploring a level thoroughly';
use constant references => ['Search','ExploreViaTeleport'];

__PACKAGE__->meta->make_immutable;
no Moose;

1;
