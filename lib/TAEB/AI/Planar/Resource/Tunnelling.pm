#!/usr/bin/env perl
package TAEB::AI::Planar::Resource::Tunnelling;
use TAEB::OO;
use Moose;
extends 'TAEB::AI::Planar::Resource';

# It's nice if we can dig.  Very nice.  Also very plentiful since digging
# tools are indefinitely reusable.
has (_value => (
    isa     => 'Num',
    is      => 'rw',
    default => 500,
));

sub is_lasting { 1 }

sub amount {
    return TAEB->has_item(['pick-axe', 'dwarvish mattock']) ? 1e8 : 0;
}

# A second source is useless
sub scarcity {
    my ($self, $quantity) = @_;
    $quantity > 1.1e8 ? 0 : 1e-8
}

sub want_to_spend { }

__PACKAGE__->meta->make_immutable;
no Moose;

1;
