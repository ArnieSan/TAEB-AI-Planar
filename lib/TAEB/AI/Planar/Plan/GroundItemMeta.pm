#!/usr/bin/env perl
package TAEB::AI::Planar::Plan::GroundItemMeta;
use TAEB::OO;
use TAEB::Util qw/refaddr/;
use Moose;
extends 'TAEB::AI::Planar::Plan';

# A plan that does nothing but create other plans, as appropriate to
# the item in question.

# We take an item as argument.
has item => (
    isa     => 'Maybe[NetHack::Item]',
    is      => 'rw',
    default => undef,
);
sub set_arg {
    my $self = shift;
    $self->item(shift);
}

# Remember which items we decided were useless to pick up, and the
# aisteps we decided that on.
has useless_items => (
    isa     => 'HashRef[Int]',
    is      => 'rw',
    default => sub { {} },
);

# Ensure plans exist for everything that the given item can do. This
# is generally done by getting the plan with get_plan, then validating
# the result; this is because get_plan ensures that the plan exists.
sub planspawn {
    my $self = shift;
    my $ai = TAEB->ai;
    my $item = $self->item;
    # Create plans to eat food.
    if ($item->isa("TAEB::World::Item::Food::Corpse")) {
	$ai->get_plan('FloorFood',$item)->validate;
    } elsif ($item->isa("TAEB::World::Item::Food") &&
             $item->name !~ /\begg\b/o &&
             $item->is_safely_edible) {
        $ai->get_plan('PermaFloorFood',$item)->validate;
    }
    # Pick up items if they seem useful. We check each item only once
    # every 50 turns if we previously found it useless (it's unlikely
    # to spontaneously become useful), and recheck on the turn after a
    # pickup or drop. (Useful items, of course, get checked every
    # step, because risk fluctuates a lot.)
    my $aistep = $ai->aistep;
    return if ($self->useless_items->{refaddr $item} // -1) > $aistep &&
        (!$ai->old_plans->[0] ||
         $ai->old_plans->[0]->name !~ /^(?:PickupItem|Drop)/o);
    if ($ai->item_value($item) > 0) {
	$ai->get_plan($self->item_tile($item)->in_shop ?
                      'BuyItem' : 'PickupItem',$item)->validate;
    } else {
        $self->useless_items->{refaddr $item} = $aistep+50;
    }
}

sub invalidate {shift->validity(0);}

use constant description => 'Doing something with an item on the ground';
use constant references => ['PickupItem','BuyItem',
                            'FloorFood','PermaFloorFood'];

__PACKAGE__->meta->make_immutable;
no Moose;

1;
