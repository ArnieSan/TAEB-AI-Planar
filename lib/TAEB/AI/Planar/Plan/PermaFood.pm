#!/usr/bin/env perl
package TAEB::AI::Planar::Plan::PermaFood;
use TAEB::OO;
use TAEB::Util qw/delta2vi/;
extends 'TAEB::AI::Planar::Plan';

# We take an item in our inventory as argument.
has item => (
    isa     => 'Maybe[TAEB::World::Item]',
    default => undef,
);
sub set_arg {
    my $self = shift;
    $self->item(shift);
}

# This is resource conversion: we gain the food, for the loss of the
# item. The time spent eating it is risk rather than resource loss.
sub gain_resource_conversion_desire {
    my $self = shift;
    my $ai   = TAEB->personality;
    my $item = $self->item;
    # Bump our own desirability.
    $ai->add_capped_desire($self, $ai->resources->{'Nutrition'}->value *
			   $item->nutrition - $ai->item_value($item));
}

sub calculate_risk {
    my $self = shift;
    my $item = $self->item;
    my $risk = 0;
    $risk += $self->cost('Time',$item->time) if defined $item->time;
    return $risk;
}

# This plan needs a continuous stream of validity from our inventory,
# or it ceases to exist.
sub invalidate {shift->validity(0);}

sub action {
    my $self = shift;
    my $item = $self->item;
    return undef unless defined $item;
    return TAEB::Action->new_action('eat', item => $item);
}

use constant description => 'Eating food in our inventory';

__PACKAGE__->meta->make_immutable;
no Moose;

1;
