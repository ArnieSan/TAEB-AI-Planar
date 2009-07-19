#!/usr/bin/env perl
package TAEB::AI::Planar::Plan::GetTheLuckstone;
use TAEB::OO;
extends 'TAEB::AI::Planar::Plan';

sub spread_desirability {
    my $self = shift;

    # if we're in the dungeons below 4, GET OUT
    if ((TAEB->current_level->branch // 'mines') ne 'mines' && TAEB->z > 4) {
	$self->depends(1,"Shallower");
	return;
    }

    my $seen_mines = 0;

    for my $stratum (@{TAEB->dungeon->levels}) {
	my ($mines) = grep { ($_->branch // '') eq 'mines' } @$stratum;

	for my $level (@$stratum) {
	    next if ($level->branch // 'mines') ne 'mines' && $level->z > 4;
	    next if defined $mines && $level != $mines;
	    $self->depends(1 - 0.005 * $level->z, "ExploreLevel", $level);

	    for my $exit ($level->exits) {
		$self->depends(1 - 0.005 * $level->z, "OtherSide", $exit)
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
