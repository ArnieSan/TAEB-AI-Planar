#!/usr/bin/env perl
package TAEB::AI::Planar::Plan::PushBoulderRisky;
use TAEB::OO;
use TAEB::Util qw/delta2vi/;
use Moose;
extends 'TAEB::AI::Planar::Plan::PushBoulder';

# Mostly the same as PushBoulder, but we want to add a larger penalty
sub calculate_risk {
    my $self = shift;
    my $tme  = shift;
    my $tile = $self->tile;
    $self->cost("Time",5); # add a large don't-do-this penalty
    $self->level_step_danger($tile->level) for 1..5;
}

use constant description => "Pushing a boulder we don't really want to move";

__PACKAGE__->meta->make_immutable;
no Moose;

1;
