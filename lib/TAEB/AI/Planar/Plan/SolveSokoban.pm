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
    # If we aren't in Sokoban, bail.
    TAEB->current_level->known_branch && TAEB->current_level->branch eq 'sokoban'
        or return undef;
    # Consult the spoilers for this level to see where to go next.
    my $nexttile = TAEB::Spoilers::Sokoban->next_sokoban_step(TAEB->current_level);
    # Nowhere?
    return undef unless defined $nexttile;
    # To an empty square?
    return $nexttile unless $nexttile->has_boulder;
    # Or to push a boulder?
    my $p = $self->push_in_row;
    $self->bouldertile($nexttile);
    $self->push_turn == TAEB->turn ? $p++ : ($p = 0);
    $self->need_to_wait($p > 3);
    $self->push_in_row($p);
    $self->push_turn(TAEB->turn);
    return TAEB->current_tile;
}

sub has_reach_action { 1 }
sub reach_action {
    my $self = shift;
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
    # If we're on the same aistep as before, there must be a monster
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

sub spread_desirability {
    my $self = shift;
    # TODO: Don't fallback if Sokoban is unsolvable

    # If we're in Sokoban already, fall back to Ascend. This means that if the
    # current level is solved, we'll go up to the next one; and if it isn't,
    # Ascend won't be able to succeed, so the AI will go and do something else.
    TAEB->current_level->known_branch && TAEB->current_level->branch eq 'sokoban'
        and $self->depends(1,"Ascend"), return;
    # Otherwise, go to Sokoban.
    $self->depends(1,"GotoSokoban");
}

use constant description => 'Solving Sokoban';
use constant references => ['Ascend','GotoSokoban'];

__PACKAGE__->meta->make_immutable;
no Moose;

1;
