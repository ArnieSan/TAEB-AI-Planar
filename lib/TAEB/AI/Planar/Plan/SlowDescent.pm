#!/usr/bin/env perl
package TAEB::AI::Planar::Plan::SlowDescent;
use TAEB::OO;
use TAEB::Spoilers::Sokoban;
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
        $level == TAEB->current_level and $seenthislevel = 1;
        # If this is a Sokoban level, solve it; otherwise, explore it.
        # For now, avoid the mines.
        if($level->known_branch && $level->branch eq 'sokoban') {
            $seensoko or
                TAEB::Spoilers::Sokoban->number_of_solved_sokoban_levels == 4
                or $self->depends($urgency+0.0005,'SolveSokoban');
            $seensoko or TAEB->log->ai(
                TAEB::Spoilers::Sokoban->number_of_solved_sokoban_levels .
                " Sokoban levels solved.");
            TAEB->log->ai(
                TAEB::Spoilers::Sokoban->recognise_sokoban_variant($level).
                " has " . TAEB::Spoilers::Sokoban->remaining_pits($level) .
                " pits left.");
            $seensoko = 1;
            $level->has_type('stairsup') ||
                TAEB::Spoilers::Sokoban->remaining_pits($level) or
                TAEB->log->ai("I want to explore the top of Sokoban"),
                $self->depends($urgency+0.0005,'ExploreLevel',$level);
        }
        if(!$level->known_branch ||
           ($level->branch ne 'mines' && $level->branch ne 'sokoban')) {
            $self->depends($urgency,'ExploreLevel',$level);
            $self->depends(1.8-$urgency,'FallbackExplore',$level);
        }
        # We need to avoid the fallback on ExploreLevel for levels
        # other than ones for which we can see 2+ stairs; otherwise,
        # we search high levels rather than levels on which the search
        # fallback is needed. This excludes levels which are only meant
        # to have one exit. TODO: that's more levels than level 1.
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
