#!/usr/bin/env perl
package TAEB::AI::Planar::Resource::Delta;
use TAEB::OO;
extends 'TAEB::AI::Planar::Resource';

# General notes: a delta is an almost worthless resource that exists
# as a tiebreaker. If something is marginally less optimal than
# something else on general principles, making it cost one or more
# deltas more is the best way to deal with that.

# We have as many deltas as we need.
sub amount {
    return 1e6;
}

# Deltas are tiny.
sub value {
    return 1e-7;
}

# Deltas never run out.
sub scarcity {
    return 1;
}

# Spending deltas doesn't adjust their value.
sub want_to_spend { }

__PACKAGE__->meta->make_immutable;
no Moose;

1;
