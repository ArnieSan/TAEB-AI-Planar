#!/usr/bin/env perl
package TAEB::AI::Planar::Plan::DevNullSokobanMeta;
use TAEB::OO;
use Moose;
extends 'TAEB::AI::Planar::Plan';

# Gets us the Sokoban prize, with no restrictions on what we do with
# it after then.
sub spread_desirability {
    my $self = shift;
    $self->depends(0.9,"SolveSokoban");
    $self->depends(1,"SokobanPrize");
    $self->depends(0.5,"SlowDescent"); # what to do after
}

use constant description => 'Trying to get the Sokoban star in /dev/null';
use constant references => ['SolveSokoban','SokobanPrize','SlowDescent'];

__PACKAGE__->meta->make_immutable;
no Moose;

1;
