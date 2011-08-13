#!/usr/bin/env perl
package TAEB::AI::Planar::Plan::PushBoulder;
use TAEB::OO;
use TAEB::Util qw/delta2vi/;
use Moose;
extends 'TAEB::AI::Planar::Plan::DirectionalTactic';

sub calculate_risk {
    my $self = shift;
    my $tme  = shift;
    my $tile = $self->tile($tme);
    $self->cost("Time",1);
    $self->level_step_danger($tile->level);
}

sub check_possibility {
    my $self = shift;
    my $tme  = shift;
    $self->add_directional_move($tme);
}

sub action {
    my $self = shift;
    $self->tile; # memorize it
    return TAEB::Action->new_action('move', direction => $self->dir);
}

sub succeeded {
    my $self = shift;
    return TAEB->current_tile == $self->memorized_tile;
}

use constant description => 'Pushing a boulder';

__PACKAGE__->meta->make_immutable;
no Moose;

1;
