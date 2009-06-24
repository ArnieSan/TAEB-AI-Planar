#!/usr/bin/env perl
package TAEB::AI::Planar::Plan::GotoSokoban;
use TAEB::OO;
use TAEB::Util qw/delta2vi/;
extends 'TAEB::AI::Planar::Plan::Strategic';

has _level => (
    isa => 'Maybe[TAEB::World::Level]',
    is  => 'rw',
);

sub aim_tile {
    # If we're already in Sokoban, bail.
    TAEB->current_level->known_branch && TAEB->current_level->branch eq 'sokoban'
        and return undef;
    # If we aren't in the Dungeons, bail.
    TAEB->current_level->known_branch && TAEB->current_level->branch eq 'dungeons'
        or return undef;
    shift->_level(TAEB->current_level);
    # Look for upstairs on this level.
    my @stairslist = ();
    TAEB->current_level->each_tile(sub {
        my $tile = shift;
        $tile->type eq 'stairsup' && push @stairslist, $tile;});
    # If we know the other side goes to Sokoban, use it.
    defined $_->other_side &&
        $_->other_side->known_branch && $_->other_side->branch eq 'sokoban'
        and return $_ for @stairslist;
    # If we're in the Dungeons, and there are two upstairs, the one we don't
    # know the other side of must go to Sokoban. (Or be a mimic.)
    if ((scalar @stairslist) == 2) {
        defined $_->other_side && $_->other_side->known_branch
            or return $_ for @stairslist;
    }
    return undef;
}

sub has_reach_action { 1 }
sub reach_action {
    return TAEB::Action->new_action('ascend');
}
sub reach_action_succeeded {
    my $self = shift;
    # If we went downstairs, it worked.
    return TAEB->current_level != $self->_level;
}

sub calculate_extra_risk {
    my $self = shift;
    return $self->cost('Time', 1);
}

sub spread_desirability {
    my $self = shift;
    # If we're in Sokoban already, nothing we can do will help.
    TAEB->current_level->known_branch && TAEB->current_level->branch eq 'sokoban'
        and return;
    # If we aren't in the dungeons, go there.
    TAEB->current_level->known_branch && TAEB->current_level->branch eq 'dungeons'
        or $self->depends(1,"GotoDungeons"), return;
    # Find the Oracle level.
    my $oracle = TAEB->dungeon->special_level->{'oracle'};
    # If we don't know where it is, descend whilst avoiding the Mines.
    # (TODO: VerticalConnectivity?)
    $self->depends(1,"DescendAvoidingMines"), return unless defined $oracle;
    # If we're on the Oracle level, or above it, descend.
    $self->depends(1,"DescendAvoidingMines"), return
        if TAEB->current_level->z <= $oracle->z;
    # If we're two or more levels below the Oracle level, ascend.
    $self->depends(1,"Ascend"), return if TAEB->current_level->z >= $oracle->z + 2;
    # Otherwise, explore this level to find the stairs leading to Sokoban.
    $self->depends(1,"ExploreHere");
}

use constant description => 'Going to Sokoban';
use constant references => ['ExploreHere','DescendAvoidingMines',
                            'Ascend','GotoDungeons'];

__PACKAGE__->meta->make_immutable;
no Moose;

1;
