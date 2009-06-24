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
                or $self->depends($urgency,'Eliminate',$_)
                for TAEB->current_level->has_enemies;
            $seenthislevel = 1;
        }
        # If this is a Sokoban level, solve it; otherwise, explore it.
        if($level->known_branch && $level->branch eq 'sokoban') {
            $seensoko and $self->depends($urgency,'SolveSokoban');
            $seensoko = 1;
        } else {
            $self->depends($urgency,'ExploreLevel',$level);
        }
        return 0;
    });
    # If the current level isn't connected in the dungeon graph, explore it
    # until we find stairs for OtherSide to climb.
    $seenthislevel or $self->depends($urgency,'ExploreHere');
}

use constant description => 'Exploring the dungeon slowly';
use constant references => ['ExploreLevel','ExploreHere',
                            'SolveSokoban','Eliminate','OtherSide'];

__PACKAGE__->meta->make_immutable;
no Moose;

1;
