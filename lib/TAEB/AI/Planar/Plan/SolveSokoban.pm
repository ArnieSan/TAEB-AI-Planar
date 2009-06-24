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
    # Try to discover a Sokoban level to solve.
    my $sokolevel = TAEB::Spoilers::Sokoban->first_unsolved_sokoban_level;
    return unless defined $sokolevel;
    # Consult the spoilers for this level to see where to go next.
    my $nexttile = TAEB::Spoilers::Sokoban->next_sokoban_step($sokolevel);
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

sub spread_desirability {
    my $self = shift;
    # If this level is solved, and it isn't the top level, and we haven't
    # seen an unsolved Sokoban level above, go up. (The last restriction is
    # because interlevel pathing is better than Ascend for going to known
    # levels.)
    my $variant = TAEB::Spoilers::Sokoban->recognise_sokoban_variant;
    $variant =~ /soko[234]\-./
        and TAEB::Spoilers::Sokoban->remaining_pits == 0
        and !defined TAEB::Spoilers::Sokoban->first_unsolved_sokoban_level
        and $self->depends(1,"Ascend"), return;
    # If we're in Sokoban already, try exploring around to see if there
    # are mimics pretending to be boulders.
    TAEB->current_level->known_branch && TAEB->current_level->branch eq 'sokoban'
        and $self->depends(0.5,"ImproveConnectivity"), return;
    # Otherwise, if we're outside Sokoban and haven't seen an unsolved
    # Sokoban level, go to Sokoban.
    $self->depends(1,"GotoSokoban")
        unless defined TAEB::Spoilers::Sokoban->first_unsolved_sokoban_level;
}

use constant description => 'Solving Sokoban';
use constant references => ['Ascend','GotoSokoban','ImproveConnectivity'];

__PACKAGE__->meta->make_immutable;
no Moose;

1;
