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

# Things we can do with this item.
sub planspawn {
    my $self = shift;
    my $item = $self->item;
    # Food can be eaten. This plan doesn't imply that we should eat it, or
    # that it's a good idea; just that we can.
    if($item->isa('TAEB::World::Item::Food')
    &&!$item->isa('TAEB::World::Item::Food::Corpse')
    && $item->is_safely_edible) {
	TAEB->ai->get_plan('PermaFood',$self->item)->validate;
    }
    # Pretty much anything can be dropped.
    TAEB->ai->get_plan('Drop',$self->item)->validate;
    # Weapons and armour can be equipped.
    if($item->isa("NetHack::Item::Weapon") ||
       $item->isa("NetHack::Item::Armor")) {
        TAEB->ai->get_plan('Equip',$self->item)->validate;
    }
    # UnBCUed things can be BCUed.
    if(!$item->is_blessed && !$item->is_cursed && !$item->is_uncursed) {
        TAEB->ai->get_plan('BCU',$self->item)->validate;
    }
}

sub invalidate {shift->validity(0);}

use constant description => 'Doing something with an item in inventory';
use constant references => ['PermaFood','Drop','Equip'];

__PACKAGE__->meta->make_immutable;
no Moose;

1;
