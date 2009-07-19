#!/usr/bin/env perl
package TAEB::AI::Planar::Resource::Zorkmids;
use TAEB::OO;
extends 'TAEB::AI::Planar::Resource';

sub amount {
    if (! TAEB->known_debt) {
	warn "This shouldn't happen ever, debt is unknown at next_action time";
	return 0; # rather than overestimating
    }

    return TAEB->gold - TAEB->debt;
}

# Zorkmids don't really get scarce. They can get anti-scarce, though.
sub scarcity {
    my $self = shift;
    my $quantity = shift;
    return 1 if $quantity < 1000;
    return 0.5 if $quantity < 3000;
    return 0.2 if $quantity < 10000;
    return 0.1;
}

__PACKAGE__->meta->make_immutable;
no Moose;

1;
