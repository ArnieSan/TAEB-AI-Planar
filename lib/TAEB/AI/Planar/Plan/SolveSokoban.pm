#!/usr/bin/env perl
package TAEB::AI::Planar::Plan::SolveSokoban;
use TAEB::OO;
use TAEB::Util qw/delta2vi/;
use TAEB::Spoilers::Sokoban;
use Moose;
extends 'TAEB::AI::Planar::Plan::Strategic';

has (bouldertile => (
    isa => 'Maybe[TAEB::World::Tile]',
    is  => 'rw',
));
has (monster => (
    isa => 'Maybe[TAEB::World::Monster]',
    is  => 'rw',
));
has (mimictile => (
    isa => 'Maybe[TAEB::World::Tile]',
    is  => 'rw',
));
has (need_to_wait => (
    isa     => 'Bool',
    is      => 'rw',
    default => 0
));
has (push_turn => (
    isa     => 'Num',
    is      => 'rw',
    default => -1
));
has (push_backoff => (
    isa     => 'Num',
    is      => 'rw',
    default => 1
));

sub aim_tile {
    my $self = shift;
    my $ai = TAEB->ai;
    # Reset monster information.
    $self->monster(undef);
    # Try to discover a Sokoban level to solve.
    my $sokolevel = TAEB::Spoilers::Sokoban->
        first_solvable_sokoban_level(sub {defined $ai->tme_from_tile(shift);});
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
        my $variant = TAEB::Spoilers::Sokoban->recognize_sokoban_variant;
        $variant =~ /soko[234]\-./
            and TAEB::Spoilers::Sokoban->remaining_pits == 0
            and !defined TAEB::Spoilers::Sokoban->first_unsolved_sokoban_level
            and return TAEB->current_level->first_tile(
                sub {shift->type eq 'stairsup'});
        return undef;
    }
    # Wake a mimic beyond the boulder, instead of pushing at it.
    $self->monster($self->mimictile->monster)
        if $self->mimictile && $self->mimictile->glyph eq 'I';
    return undef
            if $self->mimictile
            && $self->mimictile->glyph ne $self->mimictile->floor_glyph
            && (!$self->mimictile->has_monster || $self->mimictile->glyph eq 'I')
            && $self->push_turn + $self->push_backoff >= TAEB->turn;
    # To an empty square?
    return $nexttile unless TAEB::Spoilers::Sokoban->probably_has_genuine_boulder($nexttile);
    # Or to push a boulder?
    $self->bouldertile($nexttile);
    # If there's a monster beyond the boulder, get rid of it.
    # That's done by returning undef here, and falling back to Eliminate.
    my $beyond = $nexttile->level->at_safe(
        $nexttile->x * 2 - TAEB->current_tile->x,
        $nexttile->y * 2 - TAEB->current_tile->y);
    if($beyond && $beyond->has_monster) {
        $self->monster($beyond->monster);
        $self->mimictile($beyond);
        return undef if $self->push_turn + $self->push_backoff >= TAEB->turn;
    }
    $self->push_turn(TAEB->turn);
    return TAEB->current_tile;
}

sub has_reach_action { 1 }
sub reach_action {
    my $self = shift;
    # Go upstairs if we're on the upstairs.
    return TAEB::Action->new_action('ascend')
        if TAEB->current_tile->type eq 'stairsup';
    # Otherwise, push the boulder.
    TAEB->log->ai("We're standing on the boulder?"),
        return undef if $self->bouldertile == TAEB->current_tile;
    return TAEB::Action->new_action('move',
        direction => delta2vi($self->bouldertile->x - TAEB->current_tile->x,
                              $self->bouldertile->y - TAEB->current_tile->y));
}

sub reach_action_succeeded {
    my $self = shift;
    # If there isn't a boulder on the square where there used to be one,
    # it worked.
    $self->push_backoff(1), return 1
        if !$self->bouldertile->has_boulder;
    # If we're on the same turn as before, there must be a monster
    # in the way, or maybe we skipped a turn due to speed; wait once,
    # and try again.
    $self->push_backoff($self->push_backoff*3), return undef
        if TAEB->turn == $self->push_turn;
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
    my $firstlevel = TAEB::Spoilers::Sokoban->first_unsolved_sokoban_level;
    my $lastlevel = TAEB::Spoilers::Sokoban->last_solved_sokoban_level;
    if (defined $lastlevel) {
        $self->depends(1,"OtherSide",$_) for $lastlevel->exits;
    }
    if (defined $firstlevel) {
        $firstlevel->each_tile(sub {
            my $tile = shift;
            if($tile->has_boulder) {
                $self->depends(1,"WakeMimic",$tile)
                    unless TAEB::Spoilers::Sokoban->
                           probably_has_genuine_boulder($tile);
            }
            if($tile->glyph eq 'm') {
                $self->depends(1,"Eliminate",$tile->monster);
            }
        });
    }
    if (TAEB->current_level->known_branch
        && TAEB->current_level->branch eq 'sokoban') {
        $self->depends(1,"Eliminate",$self->monster) if $self->monster;
        $self->depends(1,"WakeMimic",$self->mimictile)
            if $self->mimictile
            && $self->mimictile->glyph ne $self->mimictile->floor_glyph
            && (!$self->mimictile->has_monster || $self->mimictile->glyph eq 'I');
        # If a boulder and a trap are on the same square, kill the poor monster
        # trapped underneath.
        # Note: commented out until we can verify if there's a monster on
        # the square, to avoid an infinite loop
#        $_->has_boulder and
#            $self->depends(1,"MeleeHidden",$_)
#            for TAEB->current_level->tiles_of("trap");
        return;
    }
    # Otherwise, if we're outside Sokoban and haven't seen an unsolved
    # Sokoban level (or completed all four levels), go to Sokoban.
    $self->depends(1,"GotoSokoban")
        unless defined $firstlevel or
        TAEB::Spoilers::Sokoban->number_of_solved_sokoban_levels == 4;
}

use constant description => 'Solving Sokoban';
use constant references => ['GotoSokoban','Eliminate','WakeMimic','MeleeHidden'];

__PACKAGE__->meta->make_immutable;
no Moose;

1;
