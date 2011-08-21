#!/usr/bin/env perl
package TAEB::AI::Planar::Plan::PermaFloorFood;
use TAEB::OO;
use TAEB::Util qw/delta2vi/;
use Moose;
extends 'TAEB::AI::Planar::Plan::Strategic';

# We take an item on the ground as argument.
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
    my $item = $self->item;
    return unless defined $item;
    return unless $item->nutrition;
    return $self->item_tile($item);
}

sub has_reach_action { 1 }
sub reach_action {
    my $self = shift;
    my $item = $self->item;
    return unless defined $item;
    return TAEB::Action->new_action('eat', food => $item);
}

# This is resource conversion: we gain the food, for the loss of the
# item. The time spent eating it is risk rather than resource loss.
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

# This plan needs a continuous stream of validity from the ground
# or it ceases to exist.
sub invalidate {shift->validity(0);}

use constant description => 'Eating permafood on the ground';

__PACKAGE__->meta->make_immutable;
no Moose;

1;
