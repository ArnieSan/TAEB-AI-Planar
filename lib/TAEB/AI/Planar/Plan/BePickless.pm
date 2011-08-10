#!/usr/bin/env perl
return; #M::P
package TAEB::AI::Planar::Plan::BePickless;
use TAEB::OO;
use TAEB::Util qw/delta2vi/;
use Moose;
extends 'TAEB::AI::Planar::Plan::Countermeasure';

# Our argument is just outside the door of the shop, where we want
# to or would have dropped the pick.
has (doorpad => (
    isa     => 'Maybe[TAEB::World::Tile]',
    is      => 'rw',
    default => undef,
));

sub set_arg {
    my $self = shift;
    my $item = shift;
    $self->doorpad($tile);
}

sub aim_tile {
    my $self = shift;

    # If we're already in a shop, no need to do anything.
    return if TAEB->ai->door_pad(TAEB->current_tile) == $self->tile;

    # If we don't have a pick, dropping it is fruitless.
    return unless TAEB->inventory->find(['pick-axe', 'dwarvish mattock']);

    # OK.  We need to get this thing off of us.
    return $self->tile;
}

sub has_reach_action { 1 }
sub reach_action {
    my $self = shift;

    my ($pick) = TAEB->inventory->find(['pick-axe', 'dwarvish mattock']);
    return undef unless defined $pick;

    return TAEB::Action->new_action('drop', item => $pick);
}

sub calculate_extra_risk {
    my $self = shift;
    my $picks = @{[ TAEB->inventory->find(['pick-axe', 'dwarvish mattock']) ]};
    $self->aim_tile_turns($picks);
}

sub invalidate { shift->validity(0); }

use constant description => 'Going to drop our pick and enter a shop';
use constant references  => [];

__PACKAGE__->meta->make_immutable;
no Moose;

1;
