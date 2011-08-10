#!/usr/bin/env perl
package TAEB::AI::Planar::Plan::PermaFood;
use TAEB::OO;
use TAEB::Util qw/delta2vi/;
use Moose;
extends 'TAEB::AI::Planar::Plan::Strategic';

# We take an item in our inventory as argument.
has (item => (
    isa     => 'Maybe[NetHack::Item]',
    is      => 'rw',
    default => undef,
));
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
    return TAEB::Action->new_action('eat', food => $item);
}

# This is resource conversion: we gain the food, for the loss of the
# item. The time spent eating it is risk rather than resource loss.
# TODO: Gain the weight of the food as well? (Eating to satiated to
# save weight is sometimes a good idea.)
sub gain_resource_conversion_desire {
    my $self = shift;
    my $ai   = TAEB->ai;
    my $item = $self->item;
    # Bump our own desirability.
    $ai->add_capped_desire(
        $self,
        $ai->resources->{'Nutrition'}->value * $item->nutrition -
        $ai->item_value($item) / $item->quantity);
}

sub calculate_extra_risk {
    my $self = shift;
    my $item = $self->item;
    return $self->aim_tile_turns($item->time);
}

# This plan needs a continuous stream of validity from our inventory,
# or it ceases to exist.
sub invalidate {shift->validity(0);}

use constant description => 'Eating food in our inventory';

__PACKAGE__->meta->make_immutable;
no Moose;

1;
