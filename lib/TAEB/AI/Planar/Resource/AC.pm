#!/usr/bin/env perl
package TAEB::AI::Planar::Resource::AC;
use TAEB::OO;
use Moose;
extends 'TAEB::AI::Planar::Resource';

has (_value => (
    isa     => 'Num',
    is      => 'rw',
    default => 40,
));

sub is_lasting { 1 }

sub amount {
    return 10 - TAEB->ac; # counting up from 0
}

# AC becomes less important once we have better than -10.
sub scarcity {
    my $self = shift;
    my $quantity = shift;
    return 1 if $quantity < 20;
    return 0.9 if $quantity < 30;
    return 0.8 if $quantity < 40;
    return 0.7 if $quantity < 50;
    return 0.3; # not really important past -40 AC
}

__PACKAGE__->meta->make_immutable;
no Moose;

1;
