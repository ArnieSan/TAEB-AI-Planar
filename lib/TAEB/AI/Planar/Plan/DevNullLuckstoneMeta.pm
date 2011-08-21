#!/usr/bin/env perl
package TAEB::AI::Planar::Plan::DevNullLuckstoneMeta;
use TAEB::OO;
use Moose;
extends 'TAEB::AI::Planar::Plan';

sub spread_desirability {
    my $self = shift;
    my $ai = TAEB->ai;
    # More than anything else, connect the dungeon graph.
    defined $_ and $_->validity and $self->depends(1,'OtherSide',$_->tile)
        for $ai->plans_by_type('OtherSide');
    # This relies on shallowest_level short-circuiting.
    my $urgency = 0.95;
    my $seensoko = 0;
    my $seenthislevel = 0;
    my $bottommines;
    my $d1 = undef;
    my $shallowmines = TAEB->dungeon->shallowest_level(sub {
        my $l = shift; $l->known_branch && $l->branch eq 'mines'
    });
    # the first Mines level can't have a z above 5
    my $minesz = $shallowmines ? $shallowmines->z : 5;
    TAEB->dungeon->shallowest_level(sub {
        my $level = shift;
        $urgency -= 0.001;
        $d1 //= $level;
        $level == TAEB->current_level and $seenthislevel = 1;
        if(!$level->known_branch || $level->branch eq 'mines' ||
           $level->branch eq 'dungeons' && $level->z < $minesz) {
            $self->depends($urgency,'ExploreLevel',$level);
            $self->depends(1.8-$urgency,'FallbackExplore',$level);
        }
        $bottommines = $level
            if $level->known_branch && $level->branch eq 'mines';
        return 0;
    });
    # If the current level isn't connected in the dungeon graph, or if
    # we can't route to the dlvl 1 upstairs, try to go shallower.
    ($seenthislevel and $ai->tme_from_tile($d1->tiles_of('stairsup')))
        or $self->depends($urgency,'Shallower');
    # 0.9 is between ExploreLevel and FallbackExplore.
    $self->depends(0.9,'DigOutLevel', $bottommines)
        if $bottommines;
}

use constant description => 'Trying to find the Mines luckstone';
use constant references => ['Shallower', 'OtherSide', 'ExploreLevel',
                            'FallbackExplore', 'DigOutLevel'];

__PACKAGE__->meta->make_immutable;
no Moose;

1;
