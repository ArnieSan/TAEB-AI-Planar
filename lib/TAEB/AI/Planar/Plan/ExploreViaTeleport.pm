#!/usr/bin/env perl
package TAEB::AI::Planar::Plan::ExploreViaTeleport;
use TAEB::OO;
use Moose;
extends 'TAEB::AI::Planar::Plan::Strategic';

has (current_tile_memory => (
    isa     => 'Maybe[TAEB::World::Tile]',
    is      => 'rw',
    default => undef,
));
has (time_memory => (
    isa     => 'Int',
    is      => 'rw',
    default => -1,
));

sub aim_tile {
    my $self = shift;
    return unless TAEB->is_teleporting;
    # TODO: deliberate teleports with ^T, scrolls of teleport
    return TAEB->current_tile;
}

sub has_reach_action { 1 }
sub reach_action {
    my $self = shift;
    $self->current_tile_memory(TAEB->current_tile);
    $self->time_memory(TAEB->turn);
    return TAEB::Action->new_action('search', iterations => 85);
}

sub reach_action_succeded {
    my $self = shift;
    return 1 if $self->current_tile_memory != TAEB->current_tile;
    return 0 if TAEB->turn >= $self->time_memory + 85;
    return undef;
}

sub calculate_extra_risk { shift->aim_tile_turns(85); }

use constant description => 'Exploring a level via random teleport';

__PACKAGE__->meta->make_immutable;
no Moose;

1;
