#!/usr/bin/env perl
package TAEB::AI::Plan::GroundItemMeta;
use TAEB::OO;
extends 'TAEB::AI::Plan';

# A plan that does nothing but create other plans, as appropriate to
# the item in question.

# We take an item as argument.
has item => (
    isa     => 'Maybe[TAEB::World::Item]',
    default => undef,
);
sub set_arg {
    my $self = shift;
    $self->item(shift);
}

# Ensure plans exist for everything that the given item can do. This
# is generally done by getting the plan with get_plan, then ignoring
# the result; this is because get_plan ensures that the plan exists.

sub planspawn {
    my $self = shift;
    my $ai = TAEB->personality;
    my $item = $self->item;
    # Create plans to eat corpses.
    if ($item->class eq 'carrion') {
	$ai->get_plan('FloorFood',$item);
    }
    # Pick up items if they seem useful.
    if ($ai->item_value($item) > 0) {
	$ai->get_plan('PickupItem',$item);
    }
}

sub invalidate {shift->validity(0);}

use constant description => 'Doing something with an item on the ground';

__PACKAGE__->meta->make_immutable;
no Moose;

1;
