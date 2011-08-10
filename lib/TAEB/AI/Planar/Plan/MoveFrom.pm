#!/usr/bin/env perl
package TAEB::AI::Planar::Plan::MoveFrom;
use TAEB::OO;
use TAEB::AI::Planar::TacticsMapEntry;
use Moose;
extends 'TAEB::AI::Planar::Plan::Tactical';

# A metaplan. This one encompasses all methods of moving /from/ a
# particular tile; how to move off a tile depends on what type of tile
# it is. For the vast majority of tiles, movement is done via the
# MoveTo metaplan; therefore, this plan simply tells adjacent tiles
# that they can be moved to. (The only exceptions are tiles which
# can't trivially be moved from, such as lava.)

sub check_possibility_inner {
    my $self = shift;
    my $tme  = shift;
    my $ai = TAEB->ai;
    # Set off move-to metaplans for adjacent tiles.
    my $mf_cache = ($ai->plan_caches->{'MoveFrom'} //= { step => -1 });

    my $can_squeeze;
    my $sokoban = (TAEB->current_level->branch // '') eq 'sokoban';
    my $twob = $sokoban ? 'tile_walkable' : 'tile_walkable_or_boulder';

    if ($mf_cache->{step} == TAEB->ai->aistep) {
	$can_squeeze = $mf_cache->{squeeze};
    } else {
	$can_squeeze = TAEB->inventory->weight < 600 && !$sokoban;
	$mf_cache->{step} = TAEB->ai->aistep;
	$mf_cache->{squeeze} = $can_squeeze;
    }

    #D#TAEB->log->ai(sprintf (("Checking possibility of MoveFrom(%i,%i,%i), " .
    #D#	"can_squeeze = $can_squeeze"), $tme->{tile_x}, $tme->{tile_y},
    #D#	$tme->{tile_level}->z));

    my $tmetile = $self->tme_tile($tme);
    if($tmetile->type ne 'opendoor' && $tmetile->type ne 'closeddoor') {
	$tmetile->each_adjacent(sub {
	    my $tile = shift;
	    #D# TAEB->log->ai("Evaluating move (non door) to " . $tile->x . "," .
	    #D#	$tile->y);
            my $level = $tile->level;
            if (($tile->x == $tmetile->x || $tile->y == $tmetile->y) ||
		$ai->$twob($level->at($tile->x, $tmetile->y),1) ||
		$ai->$twob($level->at($tmetile->x, $tile->y),1) ||
		$can_squeeze) {
                $self->generate_plan($tme, "MoveTo", $tile);
            }
	    if (($tile->type eq 'opendoor' || $tile->type eq 'closeddoor')
		&& ($tile->x == $tmetile->x || $tile->y == $tmetile->y)) {
		# You can't move diagonally off an open door; but you
		# can close and destroy the door, then do the diagonal
		# movement. Likewise, if we want to go diagonally from
		# a closed door next to us, better plan that before we
		# start trying to walk through that.
		$tile->each_diagonal(sub {
		    my $fartile = shift;
		    return if $tmetile->x == $fartile->x;
		    return if $tmetile->y == $fartile->y;
		    $self->generate_plan($tme, "DiagonalDoor", $fartile);
		});
	    }
        });
    } else {
	# You can't move diagonally off open doors. And you can't move
	# diagonally off closed doors, once they've been opened.
	$tmetile->each_orthogonal(sub {
	    $self->generate_plan($tme, "MoveTo", shift);
        });
    }
    # It's possible to move up or down from stairs.
    if($tmetile->type eq 'stairsdown' || $tmetile->type eq 'stairsup') {
	$self->generate_plan($tme, "Stairs", $tmetile);
    }
}

use constant references => ['MoveTo','DiagonalDoor','Stairs'];

__PACKAGE__->meta->make_immutable;
no Moose;

1;
