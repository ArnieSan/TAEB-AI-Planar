#!/usr/bin/env perl
package TAEB::AI::Planar::Plan::SolveSokoban;
use TAEB::OO;
use TAEB::Util qw/delta2vi/;
use TAEB::Spoilers::Sokoban;
extends 'TAEB::AI::Planar::Plan::Strategic';

has bouldertile => (
    isa => 'Maybe[TAEB::World::Tile]',
    is  => 'rw',
);
has monster => (
    isa => 'Maybe[TAEB::World::Monster]',
    is  => 'rw',
);
has need_to_wait => (
    isa     => 'Bool',
    is      => 'rw',
    default => 0
);
has push_turn => (
    isa     => 'Num',
    is      => 'rw',
    default => -1
);
has push_in_row => ( # we could be fast...
    isa     => 'Num',
    is      => 'rw',
    default => 0
);

sub aim_tile {
    my $self = shift;
    my $ai = TAEB->ai;
    # Reset monster information.
    $self->monster(undef);
    # Try to discover a Sokoban level to solve.
    my $sokolevel = TAEB::Spoilers::Sokoban->first_solvable_sokoban_level;
    return unless defined $sokolevel;
    # Consult the spoilers for this level to see where to go next.
    # Use our own tactical routing map for efficiency and correctness
    # (TAEB's built-in routing can't route past monsters, Planar can).
    my $nexttile = TAEB::Spoilers::Sokoban->next_sokoban_step(
        $sokolevel, sub {defined $ai->tme_from_tile(shift);});
    # Nowhere?
    if (!defined $nexttile) {
        # We might have completed the level; in that case, the next move
        # is upstairs.
        my $variant = TAEB::Spoilers::Sokoban->recognise_sokoban_variant;
        $variant =~ /soko[234]\-./
            and TAEB::Spoilers::Sokoban->remaining_pits == 0
            and !defined TAEB::Spoilers::Sokoban->first_unsolved_sokoban_level
            and return TAEB->current_level->first_tile(
                sub {shift->type eq 'stairsup'});
        return undef;
    }
    # To an empty square?
    return $nexttile unless $nexttile->has_boulder;
    # Or to push a boulder?
    my $p = $self->push_in_row;
    $self->bouldertile($nexttile);
    # If there's a monster beyond the boulder, get rid of it.
    # That's done by returning undef here, and falling back to Eliminate.
    my $beyond = $nexttile->level->at_safe(
        $nexttile->x * 2 - TAEB->current_tile->x,
        $nexttile->y * 2 - TAEB->current_tile->y);
    if($beyond && $beyond->has_monster) {
        $self->monster($beyond->monster);
        return undef;
    }
    $self->push_turn == TAEB->turn ? $p++ : ($p = 0);
    $self->need_to_wait($p > 3);
    $self->push_in_row($p);
    $self->push_turn(TAEB->turn);
    return TAEB->current_tile;
}

sub has_reach_action { 1 }
sub reach_action {
    my $self = shift;
    # Go upstairs if we're on the upstairs.
    return TAEB::Action->new_action('ascend')
        if TAEB->current_tile->type eq 'stairsup';
    # Wait 1 turn if we tried to push a boulder and it didn't move.
    return TAEB::Action->new_action('search', iterations => 1)
        if $self->need_to_wait;
    # Otherwise, push the boulder.
    return TAEB::Action->new_action('move',
        direction => delta2vi($self->bouldertile->x - TAEB->current_tile->x,
                              $self->bouldertile->y - TAEB->current_tile->y));
}

sub reach_action_succeeded {
    my $self = shift;
    # If there isn't a boulder on the square where there used to be one,
    # it worked.
    return 1 if !$self->bouldertile->has_boulder;
    # If we're on the same turn as before, there must be a monster
    # in the way, or maybe we skipped a turn due to speed; wait once,
    # and try again.
    return undef if TAEB->turn == $self->push_turn;
    # Otherwise, we failed.
    return 0;
}

sub calculate_extra_risk {
    my $self = shift;
    return $self->aim_tile_turns(1);
}

# This plan cannot be abandoned when in Sokoban.
sub abandon {
    my $self = shift;
    TAEB->current_level->known_branch
        and TAEB->current_level->branch eq 'sokoban'
        and return;
    $self->mark_impossible(3);
}

sub spread_desirability {
    my $self = shift;
    # If this level is solved, and it isn't the top level, and we
    # haven't seen an unsolved Sokoban level above, go up. (The last
    # restriction is because interlevel pathing is better than Ascend
    # for going to known levels.) If we're in Sokoban already, try
    # exploring around to see if there are mimics pretending to be
    # boulders, and killing monsters that are in the way.
    if (TAEB->current_level->known_branch
        && TAEB->current_level->branch eq 'sokoban')
    {
        $self->depends(1,"Eliminate",$self->monster) if $self->monster;
        $self->depends(1,"OtherSide",$_) for TAEB->current_level->exits;
        $self->depends(0.5,"ExploreHere");
        return;
    }
    # Otherwise, if we're outside Sokoban and haven't seen an unsolved
    # Sokoban level, go to Sokoban.
    $self->depends(1,"GotoSokoban")
        unless defined TAEB::Spoilers::Sokoban->first_unsolved_sokoban_level;
}

use constant description => 'Solving Sokoban';
use constant references => ['GotoSokoban','ExploreHere','Eliminate'];

__PACKAGE__->meta->make_immutable;
no Moose;

1;
