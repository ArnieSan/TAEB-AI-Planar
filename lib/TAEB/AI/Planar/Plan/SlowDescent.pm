#!/usr/bin/env perl
package TAEB::AI::Planar::Plan::SlowDescent;
use TAEB::OO;
extends 'TAEB::AI::Planar::Plan';

sub spread_desirability {
    my $self = shift;
    # More than anything else, connect the dungeon graph.
    defined $_ and $_->validity and $self->depends(1,'OtherSide',$_->tile)
        for @{TAEB->ai->plan_index_by_type->{'OtherSide'}};
    # This relies on shallowest_level short-circuiting.
    my $urgency = 1;
    my $seensoko = 0;
    my $seenthislevel = 0;
    TAEB->dungeon->shallowest_level(sub {
        my $level = shift;
        $urgency -= 0.001;
        # Eliminate monsters on the current level with the same urgency as
        # exploring it / solving it.
        if($level == TAEB->current_level) {
            TAEB->ai->monster_is_peaceful($_)
                or $_->tile->in_shop
                or $self->depends($urgency,'Eliminate',$_)
                for TAEB->current_level->has_enemies;
            $seenthislevel = 1;
        }
        # If this is a Sokoban level, solve it; otherwise, explore it.
        # For now, avoid the mines.
        if($level->known_branch && $level->branch eq 'sokoban') {
            $seensoko and $self->depends($urgency,'SolveSokoban');
            $seensoko = 1;
        } elsif(!$level->known_branch || $level->branch ne 'mines') {
            $self->depends($urgency,'ExploreLevel',$level);
        }
        # We need to avoid the fallback on ExploreLevel for levels
        # other than ones for which we can see 2+ stairs; otherwise,
        # we search high levels rather than levels on which the search
        # fallback is needed. This excludes levels which are only meant
        # to have one exit. TODO: that's more levels than level 1.
        scalar $level->exits < 2 and $level->z != 1
            and $self->depends(0.8,'FallbackExplore',$level);
        return 0;
    });
    # If the current level isn't connected in the dungeon graph, try to
    # go shallower.
    $seenthislevel or $self->depends($urgency,'Shallower');
}

use constant description => 'Exploring the dungeon from top to bottom';
use constant references => ['ExploreLevel','Shallower','FallbackExplore',
                            'SolveSokoban','Eliminate','OtherSide'];

__PACKAGE__->meta->make_immutable;
no Moose;

1;
