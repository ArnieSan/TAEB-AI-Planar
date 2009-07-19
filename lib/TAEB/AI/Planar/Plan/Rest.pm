#!/usr/bin/env perl
package TAEB::AI::Planar::Plan::Rest;
use TAEB::OO;
extends 'TAEB::AI::Planar::Plan::Strategic';

sub aim_tile {
    my $self = shift;
    return unless TAEB->hp * 2 < TAEB->maxhp; #XXX
    return TAEB->current_tile;
}

sub has_reach_action { 1 }
sub reach_action {
    my $self = shift;
    return TAEB::Action->new_action('search');
}

sub gain_resource_conversion_desire {
    my $self = shift;
    my $ai   = TAEB->ai;
    # Bump our own desirability.
    my $rr;

    if (TAEB->polyself) {
	$rr = 0.05;
    } elsif (TAEB->level > 9 && TAEB->con <= 12) {
	$rr = 1/3;
    } elsif (TAEB->level > 9) {
	$rr = 0;
	for my $roll (1 .. TAEB->con) {
	    $rr += ($roll > TAEB->level - 9) ? TAEB->level - 9 : $roll;
	}
	$rr /= TAEB->con;
    } else {
	$rr = 1 / int(42 / (TAEB->level + 2) + 1); #wtf?
    }

    $ai->add_capped_desire($self,
	$ai->resources->{'Hitpoints'}->anticost($rr * 20));
}

sub calculate_extra_risk { shift->aim_tile_turns(20); }

# This plan is always valid
sub invalidate { }

use constant description => 'Resting for HP';

__PACKAGE__->meta->make_immutable;
no Moose;

1;
