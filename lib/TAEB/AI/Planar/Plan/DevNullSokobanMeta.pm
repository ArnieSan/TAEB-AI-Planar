#!/usr/bin/env perl
package TAEB::AI::Planar::Plan::DevNullSokobanMeta;
use TAEB::OO;
use Moose;
extends 'TAEB::AI::Planar::Plan';

# Gets us the Sokoban prize, with no restrictions on what we do with
# it after then.
sub spread_desirability {
    my $self = shift;
    $self->depends(0.9,"SlowDescent");
    $self->depends(1,"SokobanPrize");
}

use constant description => 'Trying to get the Sokoban star in /dev/null';
use constant references => ['SlowDescent','SokobanPrize'];

__PACKAGE__->meta->make_immutable;
no Moose;

1;
