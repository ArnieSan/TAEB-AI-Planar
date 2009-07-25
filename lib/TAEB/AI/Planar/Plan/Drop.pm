#!/usr/bin/env perl
package TAEB::AI::Planar::Plan::Drop;
use TAEB::OO;
use TAEB::Util qw/delta2vi/;
extends 'TAEB::AI::Planar::Plan::Strategic';

# We take an item in our inventory as argument.
has item => (
    isa     => 'Maybe[NetHack::Item]',
    is      => 'rw',
    default => undef,
);
sub set_arg {
    my $self = shift;
    $self->item(shift);
}

sub aim_tile {
    my $self = shift;
    return undef unless defined $self->item;
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

# Dropping an item gains us its drawbacks, but loses us its advantages.
sub gain_resource_conversion_desire {
    my $self = shift;
    my $ai   = TAEB->ai;
    my $item = $self->item;
    # Bump our own desirability.
    $self->validity(0), return 0 unless defined $self->item;
    my ($affordable, $cost) = $ai->item_drawback_cost($item,'anticost');
    my $value = $ai->item_value($item, 'cost');
    # If an item breaks resource constraints, drop it no matter how
    # useful it is.
    $value = 0 unless $affordable;
    TAEB->log->ai("$item: value $value, cost $cost");
    $ai->add_capped_desire($self, $cost - $value);
}

sub calculate_extra_risk {
    my $self = shift;
    return $self->aim_tile_turns(1);
}

sub reach_action_succeeded {
    my $item = shift->item;
    return !defined $item->slot; # if it isn't in our inventory, it worked
}

# This plan needs a continuous stream of validity from our inventory,
# or it ceases to exist.
sub invalidate {shift->validity(0);}

use constant description => 'Dropping an unwanted item';

__PACKAGE__->meta->make_immutable;
no Moose;

1;
