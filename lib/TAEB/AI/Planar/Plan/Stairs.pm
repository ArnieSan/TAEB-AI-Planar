#!/usr/bin/env perl
package TAEB::AI::Planar::Plan::Stairs;
use TAEB::OO;
use TAEB::Util qw/delta2vi/;
extends 'TAEB::AI::Planar::Plan::Tactical';

has tile => (
    isa => 'Maybe[TAEB::World::Tile]',
    is  => 'rw',
    default => undef,
);
sub set_additional_args {
    my $self = shift;
    $self->tile(shift);
}

sub calculate_risk {
    my $self = shift;
    my $tme  = shift;
    my $tile = $self->tile;
    $self->cost("Time",1);
    $self->level_step_danger($tile->other_side->level);
}

sub check_possibility_inner {
    my $self = shift;
    my $tme  = shift;
    my $tile = $self->tile->other_side;
    return unless defined $tile; # if we don't know where they go, then...
    $self->add_possible_move($tme,$tile->x,$tile->y,$tile->level);
}

sub action {
    my $self = shift;
    my $tile = $self->tile;
    return TAEB::Action->new_action('ascend') if $tile->type eq 'stairsup';
    return TAEB::Action->new_action('descend') if $tile->type eq 'stairsdown';
    return undef;
}

sub succeeded {
    my $self = shift;
    return 0 unless $self->tile->type =~ /^stairs/o;
    return TAEB->current_tile == $self->tile->other_side;
}

use constant description => 'Using stairs';

__PACKAGE__->meta->make_immutable;
no Moose;

1;
