#!/usr/bin/env perl
package TAEB::AI::Planar::Plan::CombatFallback;
use TAEB::OO;
use Moose;
extends 'TAEB::AI::Planar::Plan';

sub spread_desirability {
    my $self = shift;
    $self->depends(1,"PrayForHealth");
    $self->depends(0.2,"EmergencyElbereth");
    $self->depends(0.18,"EmergencyMelee");
}

use constant description => 'Trying a fallback combat strategy';
use constant references => ['PrayForHealth','EmergencyElbereth','EmergencyMelee'];

__PACKAGE__->meta->make_immutable;
no Moose;

1;
