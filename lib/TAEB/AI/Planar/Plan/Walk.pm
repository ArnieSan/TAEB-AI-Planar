#!/usr/bin/env perl
package TAEB::AI::Planar::Plan::Walk;
use TAEB::OO;
use TAEB::Util qw/delta2vi/;
use Moose;
extends 'TAEB::AI::Planar::Plan::DirectionalTactic';
with 'TAEB::AI::Planar::Meta::Role::SqueezeChecked';

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
    my $tile = $self->tile($tme);
    return unless TAEB->ai->tile_walkable($tile);
    $self->add_directional_move($tme);
}

sub replaceable_with_travel { 1 }
sub action {
    my $self = shift;
    $self->tile; # memorize tile
    return TAEB::Action->new_action('move', direction => $self->dir);
}

sub succeeded {
    my $self = shift;
    return TAEB->current_tile == $self->memorized_tile;
}

use constant description => 'Walking';

__PACKAGE__->meta->make_immutable;
no Moose;

1;
