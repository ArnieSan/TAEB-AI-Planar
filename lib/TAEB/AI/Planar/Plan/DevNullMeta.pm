#!/usr/bin/env perl
package TAEB::AI::Planar::Plan::DevNullMeta;
use TAEB::OO;
use Moose;
extends 'TAEB::AI::Planar::Plan';

# Dives for the Sokoban prize, with no restrictions on what we do with
# it after then; then starts clearing to the Mines.
sub spread_desirability {
    my $self = shift;
    $self->depends(1,"SokobanPrize");
    $self->depends(0.9,"SolveSokoban");
    $self->depends(0.4,"DevNullLuckstoneMeta");
    $self->depends(0.15,"SlowDescent");
}

use constant description => 'Trying to get /dev/null stars';
use constant references => ['SolveSokoban','SokobanPrize','DevNullLuckstoneMeta',
                            'SlowDescent'];

__PACKAGE__->meta->make_immutable;
no Moose;

1;
