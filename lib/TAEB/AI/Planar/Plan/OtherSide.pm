#!/usr/bin/env perl
package TAEB::AI::Planar::Plan::OtherSide;
use TAEB::OO;
use Moose;
extends 'TAEB::AI::Planar::Plan::Strategic';

# We take a tile as argument.
has (tile => (
    isa     => 'Maybe[TAEB::World::Tile]',
    is  => 'rw',
    default => undef,
));
sub set_arg {
    my $self = shift;
    $self->tile(shift);
}

has (_level => (
    isa => 'Maybe[TAEB::World::Level]',
    is  => 'rw',
));

sub invalidate { shift->validity(0); }

sub aim_tile {
    my $self = shift;
    $self->validity(0), return if defined $self->tile->other_side;
    return if $self->tile->z == 1 && $self->tile->type eq 'stairsup';
    $self->_level(TAEB->current_level);
    return $self->tile;
}

sub has_reach_action { 1 }
sub reach_action {
    my $self = shift;
    return TAEB::Action->new_action('ascend')
        if $self->tile->type eq 'stairsup';
    return TAEB::Action->new_action('descend')
        if $self->tile->type eq 'stairsdown';
    return;
}
sub reach_action_succeeded {
    my $self = shift;
    # If we're on a different level, it worked.
    return TAEB->current_level != $self->_level;
}
sub calculate_extra_risk {
    my $self = shift;
    return $self->cost('Time', 1);
}

sub spread_desirability {
    my $self = shift;
    # No point in exploring if we failed due to not wanting to see
    # the other side of the stairs on dlvl 1.
    return if $self->tile->z == 1 && $self->tile->type eq 'stairsup';
    # If we can't route to the stairs, explore the level they're on.
    # TODO: directed exploration?
    $self->depends(1,"ExploreLevel", $self->tile->level);
}

use constant description => "Looking at the other side of stairs";

__PACKAGE__->meta->make_immutable;
no Moose;

1;
