#!/usr/bin/env perl
package TAEB::AI::Planar::Plan::LightTheWay;
use TAEB::OO;
use TAEB::Util qw/delta2vi/;
use Moose;
extends 'TAEB::AI::Planar::Plan::DirectionalTactic';

sub calculate_risk {
    my $self = shift;
    my $tme = shift;
    # Searching takes 1 turn. Then stepping onto the tile takes
    # another turn.
    $self->cost("Time",2);
    $self->level_step_danger($tme->{'tile_level'});
}

sub check_possibility {
    my $self = shift;
    my $tme  = shift;
    my $tile = $self->tile($tme);
    return unless $tile->type eq 'unexplored';
    $self->add_directional_move($tme);
}

sub action {
    my $self = shift;
    $self->tile; # memorize it
    return TAEB::Action->new_action('Search', iterations => 1);
}

sub succeeded {
    my $self = shift;
    # It succeeded if we can now see the tile in question.
    ($self->validity(0), return 1)
        if $self->memorized_tile->type ne 'unexplored';
    return 0;
}

use constant description => 'Searching an unexplored tile';

__PACKAGE__->meta->make_immutable;
no Moose;

1;
