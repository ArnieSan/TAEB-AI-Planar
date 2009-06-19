#!/usr/bin/env perl
package TAEB::AI::Planar::Plan::PickupItem;
use TAEB::OO;
use TAEB::Util qw/delta2vi/;
extends 'TAEB::AI::Planar::Plan::Strategic';

# We take an item on the floor as argument.
has item => (
    isa     => 'Maybe[NetHack::Item]',
    is      => 'rw',
    default => undef,
);
has tile => (
    isa     => 'Maybe[TAEB::World::Tile]',
    is      => 'rw',
    default => undef,
);

sub set_arg {
    my $self = shift;
    my $item = shift;
    $self->item($item);
    $self->tile($self->item_tile($item));
}

sub aim_tile {
    my $self = shift;
    my $item = $self->item;
    my $tile = $self->tile;
    if ($self->tile->in_shop && !($self->item->cost)) {
        # Fail in favour of AskForPrice.
        return undef;
    }
    $_ == $item and return $self->tile for $tile->items;
    $self->invalidate;
    TAEB->log->ai("Item $item has gone missing...");
    return undef;
}

# Our desire to pick something up is the value of that item.
sub gain_resource_conversion_desire {
    my $self  = shift;
    my $item  = $self->item;
    my $ai    = TAEB->ai;
    my $value = $ai->item_value($item);
    if ($value > 0) {
	$ai->add_capped_desire($self, $value);
    }
}

# TODO: Drop gold first, for credit? That helps in cases like
# leprechauns and itis.
sub has_reach_action { 1 }
sub reach_action {
    my $self = shift;
    # If the item's in a shop but we don't know how much it costs, we
    # can't buy it yet (maybe we can't afford it); use AskForPrice
    # instead.
    if ($self->tile->in_shop && !($self->item->cost)) {
        return undef;
    }
    # The actual item that's picked up depends on the personality;
    # it'll pick up all items with positive instantaneous values.
    # For some reason, the API for Pickup requires 0 to pick up all
    # items.
    return TAEB::Action->new_action('pickup', count => 0);
}
sub reach_action_succeeded {
    my $self = shift;
    # If the item is now in our inventory, it worked.
    # (We may have picked up other items at the same time, that's
    # irrelevant.)
    return defined($self->item->slot);
}

# It takes one turn to pick up the item, plus all its drawbacks (weight
# and price, in particular). One extra turn if it's in a shop and we
# don't know how much it costs.
sub calculate_extra_risk {
    my $self = shift;
    my $turncount = 1;
    my $ai = TAEB->ai;
    my $item = $self->item;
    my $drawbacks = $ai->item_drawbacks($item);
    my $risk = 0;
    for my $resourcename (keys %$drawbacks) {
	$risk += $self->cost($resourcename, $drawbacks->{$resourcename});
	# It takes a turn to pay the shk, in addition to the turn it
	# takes to pick up the item.
	$turncount++ if $resourcename eq 'Zorkmids';
    }
    return $risk + $self->aim_tile_turns($turncount);
}

sub spread_desirability {
    my $self = shift;
    if ($self->tile->in_shop && !($self->item->cost)) {
        $self->depends(1,"AskForPrice",$self->tile);
    }
}

sub invalidate { shift->validity(0); }

use constant description => 'Picking up a useful item';
use constant references  => ['AskForPrice'];

__PACKAGE__->meta->make_immutable;
no Moose;

1;
