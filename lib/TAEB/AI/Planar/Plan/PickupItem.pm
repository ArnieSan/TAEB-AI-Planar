#!/usr/bin/env perl
package TAEB::AI::Planar::Plan::PickupItem;
use TAEB::OO;
use TAEB::Util qw/delta2vi/;
extends 'TAEB::AI::Planar::Plan::PathBased';

# We take an item on the floor as argument.
has item => (
    isa     => 'Maybe[TAEB::World::Item]',
    default => undef,
);
sub set_arg {
    my $self = shift;
    $self->item(shift);
}

sub aim_tile {
    my $self = shift;
    my $item = $self->item;
    return $self->item_tile($item);
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

sub has_reach_action { 1 }
sub reach_action {
    # The actual item that's picked up depends on the personality;
    # it'll pick up all items with positive instantaneous values.
    return TAEB::Action->new_action('pickup', count => undef);
}
sub reach_action_succeeded {
    my $self = shift;
    # If the item is now in our inventory, it worked.
    # (We may have picked up other items at the same time, that's
    # irrelevant.)
    return defined($self->item->slot);
}

sub calculate_extra_risk {
    my $self = shift;
    return $self->aim_tile_turns(1);
}

use constant description => 'Picking up a useful item';

__PACKAGE__->meta->make_immutable;
no Moose;

1;
