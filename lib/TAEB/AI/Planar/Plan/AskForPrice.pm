#!/usr/bin/env perl
package TAEB::AI::Planar::Plan::AskForPrice;
use TAEB::OO;
extends 'TAEB::AI::Planar::Plan::Strategic';

# We take a tile (in a shop, with items on) as argument.
has tile => (
    isa     => 'Maybe[TAEB::World::Tile]',
    is  => 'rw',
    default => undef,
);
sub set_arg {
    my $self = shift;
    $self->tile(shift);
}

sub aim_tile {
    my $self = shift;
    my $tile = $self->tile;
    return $tile if $tile->in_shop && $tile->item_count;
    $self->validity(0);
    return undef;
}

sub has_reach_action { 1 }
sub reach_action {
    return TAEB::Action->new_action('chat');
}

sub reach_action_succeeded {
    my $self = shift;
    # We succeed if there's an item on the tile we know the cost of.
    $_->cost or return 1 for $self->tile->items;
    return 0;
}

sub calculate_extra_risk {
    my $self = shift;
    return $self->aim_tile_turns(1);
}

use constant description => "Checking an item's price";

__PACKAGE__->meta->make_immutable;
no Moose;

1;
