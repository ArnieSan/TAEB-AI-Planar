#!/usr/bin/env perl
package TAEB::AI::Planar::Plan::DevNullLuckstoneMeta;
use TAEB::OO;
extends 'TAEB::AI::Planar::Plan';

sub spread_desirability {
    my $self = shift;
    my $prio = 1;

    # if we're in the dungeons below 4, GET OUT
    if ((TAEB->current_level->branch // 'mines') ne 'mines' && TAEB->z > 4) {
	$self->depends($prio,"Shallower");
	return;
    }

    my $bottom_mines;

    for my $stratum (@{TAEB->dungeon->levels}) {
	my ($mines) = grep { ($_->branch // '') eq 'mines' } @$stratum;

	for my $level (@$stratum) {
	    next if ($level->branch // 'mines') ne 'mines' && $level->z > 4;
	    next if defined $mines && $level != $mines;
	    $self->depends($prio * 0.95 ** $level->z, "ExploreLevel", $level);
	    $bottom_mines = $level if ($level->branch // '') eq 'mines';

	    for my $exit ($level->exits) {
		$self->depends($prio * 0.95 ** $level->z, "OtherSide", $exit)
		    unless $exit->other_side;
	    }
	}
    }

    $self->depends(0.5, "DigOutLevel", $bottom_mines)
	if defined $bottom_mines;
}

use constant description => 'Getting the Plastic Star in /dev/null';
use constant references => ['Shallower', 'OtherSide', 'ExploreLevel',
    'DigOutLevel'];

__PACKAGE__->meta->make_immutable;
no Moose;

1;
