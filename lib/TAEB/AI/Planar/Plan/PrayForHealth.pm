#!/usr/bin/env perl
package TAEB::AI::Planar::Plan::PrayForHealth;
use TAEB::OO;
use TAEB::Util qw/delta2vi/;
extends 'TAEB::AI::Planar::Plan';

# As long as prayer is safe, this isn't risky at all. Not even tile risk,
# because you're invulnerable whilst praying.
sub calculate_risk {
    # Put the cost of the prayer here?
    return 0;
}

# Pray, if we can do so safely and it would heal us.
sub action {
    my $self = shift;
    return undef unless TAEB->can_pray;
    return undef unless TAEB->hp*7 < TAEB->maxhp;
    return TAEB::Action->new_action('pray');
}

use constant description => 'Praying for health';

__PACKAGE__->meta->make_immutable;
no Moose;

1;
