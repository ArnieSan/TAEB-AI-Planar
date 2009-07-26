#!/usr/bin/env perl
package TAEB::AI::Planar::Resource::Luck;
use TAEB::OO;
extends 'TAEB::AI::Planar::Resource';

has _value => (
    isa     => 'Num',
    is      => 'rw',
    default => 60,
);

sub is_lasting { 1 }

sub amount {
    return TAEB->has_item('luckstone') ? 3 : 0; #XXX
}

# You can never have too much luck.  However, you can have too little.
sub scarcity { my ($self,$qty) = @_; $qty >= 0 ? 1 : 10 }

__PACKAGE__->meta->make_immutable;
no Moose;

1;
