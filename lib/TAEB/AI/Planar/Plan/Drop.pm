#!/usr/bin/env perl
package TAEB::AI::Planar::Plan::Drop;
use TAEB::OO;
use TAEB::Util qw/delta2vi/;
use Moose;
extends 'TAEB::AI::Planar::Plan::Strategic';

# Record when the plan was created, as an aistep.
has (birthday => (
    isa     => 'Maybe[Int]',
    is      => 'rw',
    default => undef,
));

# We take an item in our inventory as argument.
has (item => (
    isa     => 'Maybe[NetHack::Item]',
    is      => 'rw',
    default => undef,
));
sub set_arg {
    my $self = shift;
    $self->item(shift);
    $self->birthday(TAEB->ai->aistep);
}

sub aim_tile {
    my $self = shift;
    return undef unless defined $self->item;
    return undef if !$self->item->can_drop;
    # Don't drop items on the Sokoban prize tile.
    my $plan = TAEB->ai->get_plan("SokobanPrize");
    return undef if $plan->prizetile
                 && $plan->prizetile == TAEB->current_tile;
    return TAEB->current_tile;
}

sub has_reach_action { 1 }
sub reach_action {
    my $self = shift;
    my $item = $self->item;
    return undef unless defined $item;
    # TODO: Drop other items at the same time?
    return TAEB::Action->new_action('drop', items => [$item]);
}

# This should really be in some module. But I don't know which offhand.
sub is_power_of_2 {
    my $arg = shift;
    return $arg && !($arg & ($arg-1));
}

# Dropping an item gains us its drawbacks, but loses us its advantages.
sub gain_resource_conversion_desire {
    my $self = shift;
    my $ai   = TAEB->ai;
    my $item = $self->item;
    # Bump our own desirability.
    $self->validity(0), return 0 unless defined $self->item;
    # As an optimisation, we don't check whether we need to drop things
    # every turn; just on turns after a pickup or drop, or if the plan
    # has existed for a power-of-2 number of aisteps.
    if (($ai->old_plans->[0] &&
         $ai->old_plans->[0]->name =~ /^(?:BuyItem|PickupItem|Drop)/o) ||
        is_power_of_2($ai->aistep - $self->birthday)) {
        my ($affordable, $cost) = $ai->item_drawback_cost($item,'anticost');
        my $value = $ai->item_value($item, 'cost');
        # If an item breaks resource constraints, drop it no matter how
        # useful it is.
        $value = 0 unless $affordable;
        TAEB->log->ai("$item: value $value, cost $cost");
        $ai->add_capped_desire($self, $cost - $value);
    }
}

sub calculate_extra_risk {
    my $self = shift;
    return $self->aim_tile_turns(1);
}

sub reach_action_succeeded {
    my $item = shift->item;
    defined $item->slot or return 1;
    TAEB->inventory->get($item->slot) and return 0;
    return 1;
}

# This plan needs a continuous stream of validity from our inventory,
# or it ceases to exist.
sub invalidate {shift->validity(0);}

use constant description => 'Dropping an unwanted item';

__PACKAGE__->meta->make_immutable;
no Moose;

1;
