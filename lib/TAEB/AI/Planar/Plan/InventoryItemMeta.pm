#!/usr/bin/env perl
package TAEB::AI::Plan::InventoryItemMeta;
use TAEB::OO;
use TAEB::Spoilers::Item::Food;
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

sub planspawn {
    my $self = shift;
    my $item = $self->item;
    if(TAEB::Spoilers::Item::Food->should_eat($item)) {
	TAEB->personality->get_plan('PermaFood',$self->item);
    }
}

sub invalidate {shift->validity(0);}

use constant description => 'Doing something with an item in inventory';

__PACKAGE__->meta->make_immutable;
no Moose;

1;
