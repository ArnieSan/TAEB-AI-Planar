#!/usr/bin/env perl
package TAEB::AI::Planar::Resource::PermaNutrition;
use TAEB::OO;
use Moose;
extends 'TAEB::AI::Planar::Resource';

has (_value => (
    isa => 'Num',
    is  => 'rw',
    default => 0.1, # twice the base value of nutrition
));

sub amount {
    my $a = 0;
    for my $item (TAEB->inventory) {
        next unless $item->isa('NetHack::Item::Food');
        next if $item->isa('NetHack::Item::Food::Corpse');
        next if !$item->is_safely_edible;
        $a += $item->nutrition * $item->quantity;
    }
    return $a;
}

# Scarcity of permanutrition gets worse the less food we have.
sub scarcity {
    my $self = shift;
    my $quantity = shift;
    ($quantity > 5000) and return 1;
    ($quantity <= 200) and return 625;
    return 25000000 / $quantity / $quantity;
}

__PACKAGE__->meta->make_immutable;
no Moose;

1;
