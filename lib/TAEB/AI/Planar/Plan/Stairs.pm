#!/usr/bin/env perl
package TAEB::AI::Planar::Plan::Stairs;
use TAEB::OO;
use TAEB::Util qw/delta2vi/;
use Moose;
extends 'TAEB::AI::Planar::Plan::ComplexTactic';

sub calculate_risk {
    my $self = shift;
    my $tme  = shift;
    $self->cost("Time",1);
    $self->level_step_danger($self->tile->level);
}

sub is_possible {
    my $self = shift;
    my $tme  = shift;
    my $tile = $self->tile_from;
    return $tile->can("other_side") && defined $tile->other_side;
}

sub action {
    my $self = shift;
    my $tile = $self->tile_from;
    return TAEB::Action->new_action('ascend') if $tile->type eq 'stairsup';
    return TAEB::Action->new_action('descend') if $tile->type eq 'stairsdown';
    return undef;
}

sub succeeded {
    my $self = shift;
    return TAEB->current_tile == $self->tile;
}

use constant description => 'Using stairs';

__PACKAGE__->meta->make_immutable;
no Moose;

1;
