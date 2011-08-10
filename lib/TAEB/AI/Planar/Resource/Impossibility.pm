#!/usr/bin/env perl
package TAEB::AI::Planar::Resource::Impossibility;
use TAEB::OO;
use Moose;
extends 'TAEB::AI::Planar::Resource';

# Impossibilities are massive.
has (_value => (
    isa     => 'Num',
    is      => 'rw',
    default => 1e7,
));

# An impossibility is the opposite of a delta; it represents the cost
# of an impossible action. This is useful only because it can be
# canceled out by a make_safer_plan that removes the impossibility;
# therefore, it's a bridge between tactics and strategy. (The concept:
# doing something tactically may be impossible [e.g. routing past a
# blue jelly], but if the AI needs to do it anyway, it can generate a
# strategy that makes it possible.)

# We don't have any impossibilities.
sub amount {
    return 0;
}

# Impossibilities don't get scarcer the more they're "used".
sub scarcity {
    return 1;
}

# Spending (or trying to spend) impossibilities doesn't adjust their value.
sub want_to_spend { }

__PACKAGE__->meta->make_immutable;
no Moose;

1;
