#!/usr/bin/env perl
package TAEB::AI::Planar::Plan::BuyItem;
use TAEB::OO;
use Moose;
extends 'TAEB::AI::Planar::Plan::PickupItem';

# Identical to PickupItem but for the name.
# This lets us buy an item after dropping a pickaxe, even though
# we can't pick up the pickaxe just after dropping it.

use constant description => 'Buying an item in a shop';

__PACKAGE__->meta->make_immutable;
no Moose;

1;
