#!/usr/bin/env perl
package TAEB::AI::Planar::Plan::MoveFrom;
use TAEB::OO;
use TAEB::AI::Planar::TacticsMapEntry;
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
    # Set off move-to metaplans for adjacent tiles.
    my $tmetile = $self->tme_tile($tme);
    if($tmetile->type ne 'opendoor') {
	$tmetile->each_adjacent(sub {
	    $self->generate_plan($tme, "MoveTo", shift);
        });
    } else {
	# You can't move diagonally off open doors.
	$tmetile->each_orthogonal(sub {
	    $self->generate_plan($tme, "MoveTo", shift);
        });
    }
    # TODO: It's possible to move up or down from stairs.
}

use constant references => ['MoveTo'];

__PACKAGE__->meta->make_immutable;
no Moose;

1;
