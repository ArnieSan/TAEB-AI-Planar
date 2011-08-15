#!/usr/bin/env perl
package TAEB::AI::Planar::Plan::GroundItemMeta;
use TAEB::OO;
use Moose;
extends 'TAEB::AI::Planar::Plan';

# A plan that does nothing but create other plans, as appropriate to
# the item in question.

# We take an item as argument.
has item => (
    isa     => 'Maybe[NetHack::Item]',
    is  => 'rw',
    default => undef,
);
sub set_arg {
    my $self = shift;
    $self->item(shift);
}

# Ensure plans exist for everything that the given item can do. This
# is generally done by getting the plan with get_plan, then validating
# the result; this is because get_plan ensures that the plan exists.
sub planspawn {
    my $self = shift;
    my $ai = TAEB->ai;
    my $item = $self->item;
    # Create plans to eat corpses.
    if ($item->isa("TAEB::World::Item::Food::Corpse")) {
	$ai->get_plan('FloorFood',$item)->validate;
    }
    # Pick up items if they seem useful.
    if ($ai->item_value($item) > 0) {
	$ai->get_plan($self->item_tile($item)->in_shop ?
                      'BuyItem' : 'PickupItem',$item)->validate;
    }
}

sub invalidate {shift->validity(0);}

use constant description => 'Doing something with an item on the ground';
use constant references => ['PickupItem','BuyItem','FloorFood'];

__PACKAGE__->meta->make_immutable;
no Moose;

1;
