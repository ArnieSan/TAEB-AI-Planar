#!/usr/bin/env perl
package TAEB::AI::Planar::Plan::PrayForHealth;
use TAEB::OO;
use TAEB::Util qw/delta2vi/;
extends 'TAEB::AI::Planar::Plan::Strategic';

# As long as prayer is safe, this isn't risky at all. Not even tile risk,
# because you're invulnerable whilst praying.
sub calculate_extra_risk {
    # Put the cost of the prayer here?
    return 0;
}

# This is only set if we can pray for health right now.
sub aim_tile {
    my $self = shift;
    return undef unless TAEB->can_pray;
    return undef unless TAEB->hp*7 < TAEB->maxhp;
    return TAEB->current_tile;
}

sub has_reach_action { 1 }
sub reach_action {
    my $self = shift;
    return TAEB::Action->new_action('pray');
}

use constant description => 'Praying for health';

__PACKAGE__->meta->make_immutable;
no Moose;

1;
