#!/usr/bin/env perl
package TAEB::AI::Planar::Plan::Nop;
use TAEB::OO;
use TAEB::AI::Planar::TacticsMapEntry;
use Moose;
extends 'TAEB::AI::Planar::Plan::Tactical';

# A tactical plan to do nothing. Needed because we have to get the
# tactics started somehow, and to stop us coming up with a more
# expensive way to route to the square we're already on.
sub set_arg { die 'This plan takes no arguments'; }

# Always possible, always trivial. Create a blank TME and send it back
# to the parent AI. This overrides the base check_possibility to stop
# it trying to update our (nonexistent) TME.
sub check_possibility {
    my $self = shift;
    my $ai   = TAEB->ai;
    my $tme = {
	prevtile_level  => undef,
	prevtile_x      => undef,
	prevtile_y      => undef,
	prevlevel_level => undef,
	prevlevel_x     => undef,
	prevlevel_y     => undef,
	risk            => {},
	level_risk      => {},
	tactic          => $self,
	tile_x          => $ai->tactical_target_tile->x,
	tile_y          => $ai->tactical_target_tile->y,
	tile_level      => $ai->tactical_target_tile->level,
	make_safer_plans=> {},
	step            => $ai->aistep,
        source          => 'nop',
    };
    bless $tme, "TAEB::AI::Planar::TacticsMapEntry";
    $ai->add_possible_move($tme);
}

sub try { die 'Attempted to try to do nothing'; }
sub succeeded { return undef; }

use constant description => 'Doing nothing [this should never come up]';

__PACKAGE__->meta->make_immutable;
no Moose;

1;
