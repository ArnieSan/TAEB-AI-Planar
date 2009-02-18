#!/usr/bin/env perl
package TAEB::AI::Planar::Plan::InventoryItemMeta;
use TAEB::OO;
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

sub planspawn {
    my $self = shift;
    my $item = $self->item;
    if($item->isa('TAEB::World::Item::Food')
    &&!$item->isa('TAEB::World::Item::Food::Corpse')
    && $item->is_safely_edible) {
	TAEB->ai->get_plan('PermaFood',$self->item);
    }
}

sub invalidate {shift->validity(0);}

use constant description => 'Doing something with an item in inventory';
use constant references => ['PermaFood'];

__PACKAGE__->meta->make_immutable;
no Moose;

1;
