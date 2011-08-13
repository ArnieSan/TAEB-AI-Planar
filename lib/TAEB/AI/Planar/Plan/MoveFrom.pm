#!/usr/bin/env perl
package TAEB::AI::Planar::Plan::MoveFrom;
use TAEB::OO;
use TAEB::AI::Planar::TacticsMapEntry;
use Moose;
extends 'TAEB::AI::Planar::Plan::Tactical';

# A metaplan. This one covers all unusual methods of moving off a tile
# that aren't simple directional movements like MoveTo handles
# (i.e. this is the metaplan for tactics that don't obey the
# restrictions of DirectionalTactic, ComplexTactics). As arguments,
# they are given the TME they move /from/ and the tile they move /to/.
# (They can use tile_from to discover the tile they move from.)

sub check_possibility {
    my $self = shift;
    my $tme  = shift;
    my $ai = TAEB->ai;
    my $tmetile = $self->tme_tile($tme);

    # It's possible to move up or down from stairs.
    if($tmetile->type eq 'stairsdown' || $tmetile->type eq 'stairsup') {
        if ($tmetile->other_side) {
            $self->generate_plan($tme, "Stairs", $tmetile->other_side);
        }
    }

    # TODO: Perhaps get DiagonalDoor working again?
}

use constant references => ['Stairs'];

__PACKAGE__->meta->make_immutable;
no Moose;

1;
