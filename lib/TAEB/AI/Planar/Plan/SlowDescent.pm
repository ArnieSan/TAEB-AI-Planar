#!/usr/bin/env perl
package TAEB::AI::Planar::Plan::SlowDescent;
use TAEB::OO;
extends 'TAEB::AI::Planar::Plan';

sub spread_desirability {
    my $self = shift;
    $self->depends(1,'ImproveConnectivity');
    $self->depends(1,'Eliminate',$_) for TAEB->current_level->has_enemies;
    $self->depends(0.95,'SolveSokoban');
    $self->depends(0.9,'Descend');
}

use constant description => 'Exploring the dungeon slowly';
use constant references => ['ImproveConnectivity','SolveSokoban','Descend',
                            'Eliminate'];

__PACKAGE__->meta->make_immutable;
no Moose;

1;
