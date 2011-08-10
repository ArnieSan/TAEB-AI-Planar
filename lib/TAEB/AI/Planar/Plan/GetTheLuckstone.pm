#!/usr/bin/env perl
package TAEB::AI::Planar::Plan::GetTheLuckstone;
use TAEB::OO;
use Moose;
extends 'TAEB::AI::Planar::Plan';

sub spread_desirability {
    my $self = shift;
    my $prio = 1;

    # if we're in the dungeons below 4, GET OUT
    if ((TAEB->current_level->branch // 'mines') ne 'mines' && TAEB->z > 4) {
	$self->depends($prio,"Shallower");
	return;
    }

    # If we have a luckstone, no point in continuing.
    return if TAEB->has_item('luckstone');

    # If we've found the mines' end luckstone, GET THAT THING
    if (defined (my $end = TAEB->dungeon->special_level->{'minend'})) {
	my @lucky = grep { $_->match(identity => 'luckstone') } $end->items;

	if (@lucky) {
	    # XXX PickupItem will crash if the item's not on the level
	    if (TAEB->current_level == $end) {
		$self->depends($prio,"PickupItem",$lucky[0]);
	    } else {
		$self->depends($prio,"ExploreLevel", $end);
	    }
	    $prio *= 0.5;
	    return unless $TAEB::AI::Planar::Plan::GetTheLuckstone::KeepLooking;
	}
    }

    my $seen_mines = 0;

    for my $stratum (@{TAEB->dungeon->levels}) {
	my ($mines) = grep { ($_->branch // '') eq 'mines' } @$stratum;

	for my $level (@$stratum) {
	    next if ($level->branch // 'mines') ne 'mines' && $level->z > 4;
	    next if defined $mines && $level != $mines;
	    $self->depends($prio * 0.95 ** $level->z, "ExploreLevel", $level);

	    for my $exit ($level->exits) {
		$self->depends($prio * 0.95 ** $level->z, "OtherSide", $exit)
		    unless $exit->other_side;
	    }
	}
    }
}

use constant description => 'Clearing towards the end of the Mines';
use constant references => ['Shallower', 'OtherSide', 'ExploreLevel'];

__PACKAGE__->meta->make_immutable;
no Moose;

1;
