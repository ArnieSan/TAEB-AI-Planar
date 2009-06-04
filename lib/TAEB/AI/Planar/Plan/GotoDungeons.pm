#!/usr/bin/env perl
package TAEB::AI::Planar::Plan::GotoDungeons;
use TAEB::OO;
use TAEB::Util qw/delta2vi/;
extends 'TAEB::AI::Planar::Plan::Strategic';

has _level => (
    isa => 'Maybe[TAEB::World::Level]',
    is  => 'rw',
);

sub aim_tile {
    # If we're already in the Dungeons, bail.
    TAEB->current_level->known_branch && TAEB->current_level->branch eq 'dungeons'
        and return undef;
    # If we don't know where we are, don't blindly aim for a known Dungeons
    # level, in case we're there already; explore instead.
    TAEB->current_level->known_branch or return undef;
    # Aim for stairs on this level which go into the dungeons.
    # (If there aren't any here, we delegate to other plans instead.)
    shift->_level(TAEB->current_level);
    return TAEB->current_level->first_tile(sub {
        my $tile = shift;
        ($tile->type eq 'stairsup' || $tile->type eq 'stairsdown') &&
            defined $tile->other_side && $tile->other_side->known_branch &&
            $tile->other_side->branch eq 'dungeons'});
}

sub has_reach_action { 1 }
sub reach_action {
    return TAEB::Action->new_action('ascend')
        if TAEB->current_tile->type eq 'stairsup';
    return TAEB::Action->new_action('descend')
        if TAEB->current_tile->type eq 'stairsdown';
}
sub reach_action_succeeded {
    my $self = shift;
    # If we're in the Dungeons, it worked.
    return TAEB->current_level->known_branch &&
        TAEB->current_level->branch eq 'dungeons';
}

sub calculate_extra_risk {
    my $self = shift;
    return $self->cost('Time', 1);
}

sub spread_desirability {
    my $self = shift;
    # If we don't know where we are, explore to find out.
    # TODO: This isn't exactly ImproveConnectivity, more DiscoverBranch. But
    # the tactics for both are much the same atm.
    TAEB->current_level->known_branch or
        $self->depends(1,'ImproveConnectivity'), return;
    # If we're in the Dungeons already, nothing we can do will help.
    TAEB->current_level->branch eq 'dungeons' and return;
    # If we're in the Mines, go up.
    TAEB->current_level->branch eq 'mines' and $self->depends(1,'Ascend'), return;
    # If we're in Sokoban, go down.
    TAEB->current_level->branch eq 'sokoban' and $self->depends(1,'Descend'), return;
    # TODO: Quest? Gehennom? Vlad's? Rodney's?
}

use constant description => 'Going to the Dungeons';
use constant references => ['Descend','Ascend','ImproveConnectivity'];

__PACKAGE__->meta->make_immutable;
no Moose;

1;
