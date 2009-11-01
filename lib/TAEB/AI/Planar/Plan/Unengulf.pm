#!/usr/bin/env perl
package TAEB::AI::Planar::Plan::Unengulf;
use TAEB::OO;
use TAEB::Util qw/delta2vi/;
extends 'TAEB::AI::Planar::Plan::Strategic';

# We can't move before attacking an engulfer.
sub aim_tile {
    TAEB->current_tile;
}
# Whack it!
sub has_reach_action { 1 }
sub reach_action {
    my $self = shift;
    return TAEB::Action->new_action('melee', direction => 'j');
}

sub calculate_extra_risk {
    my $self = shift;
    #TODO: counterattack risk
    return $self->aim_tile_turns(1) + $self->cost("Pacifism",1);
}

use constant description => 'Meleeing an engulfing monster';

__PACKAGE__->meta->make_immutable;
no Moose;

1;
