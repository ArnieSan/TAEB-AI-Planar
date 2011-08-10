#!/usr/bin/env perl
package TAEB::AI::Planar::Resource::Purity;
use TAEB::OO;
use Moose;
extends 'TAEB::AI::Planar::Resource';

# Being a lycanthrope is bad!

# Turning into wolf/rat/jackal form leads to all sorts of trouble.
has (_value => (
    isa     => 'Num',
    is      => 'rw',
    default => 60,
));

sub is_lasting { 1 }

# We have purity iff we aren't a lycanthrope.
sub amount {
    return !TAEB->is_lycanthropic;
}

# Scarcity is irrelevant for a resource with only two values.
sub scarcity {
    return 1;
}

# Spending (or trying to spend) a lack of lycanthropy has no effect.
sub want_to_spend { }

__PACKAGE__->meta->make_immutable;
no Moose;

1;
