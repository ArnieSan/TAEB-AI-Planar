#!/usr/bin/env perl
package TAEB::AI::Planar::Plan::CombatFallback;
use TAEB::OO;
extends 'TAEB::AI::Planar::Plan';

sub spread_desirability {
    my $self = shift;
    $self->depends(1,"PrayForHealth");
}

use constant description => 'Trying a fallback combat strategy';
use constant references => ['PrayForHealth'];

__PACKAGE__->meta->make_immutable;
no Moose;

1;
