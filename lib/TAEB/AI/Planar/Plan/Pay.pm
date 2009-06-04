#!/usr/bin/env perl
package TAEB::AI::Planar::Plan::Pay;
use TAEB::OO;
use TAEB::Util qw/delta2vi/;
extends 'TAEB::AI::Planar::Plan::Strategic';

# We always do payment from our current tile.
# However, this is where we fail if paying is impossible for some
# reason. The most likely reasons are lack of any debt to actually
# need to pay, and blindness.
sub aim_tile {
    my $self = shift;
    return undef unless TAEB->debt;
    return undef if TAEB->is_blind;
    return TAEB->current_tile;
}

# It takes a turn to pay for any number of items. Therefore, we may as
# well pay for them all at once; if we didn't or couldn't want to pay
# for something, we wouldn't have picked it up in the first place.
sub has_reach_action { 1 }
sub reach_action {
    my $self = shift;
    return TAEB::Action->new_action('pay', item => 'all');
}

# The Zorkmids resource doesn't count debt as part of our current gold
# supply, so this costs no Zorkmids, just time.
sub calculate_extra_risk {
    my $self = shift;
    return $self->aim_tile_turns(1);
}

use constant description => 'Paying off shop debt';

__PACKAGE__->meta->make_immutable;
no Moose;

1;
