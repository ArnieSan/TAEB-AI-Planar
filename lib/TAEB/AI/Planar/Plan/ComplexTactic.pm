#!/usr/bin/env perl
package TAEB::AI::Planar::Plan::ComplexTactic;
use TAEB::OO;
use Moose;
extends 'TAEB::AI::Planar::Plan::Tactical';

# Tactics that don't obey the restrictions of DirectionalTactic.
# These are (for the time being) represented by a TME and a tile;
# the TME is the source location, the tile is the destination.

has (tile_from => (
    isa => 'Maybe[TAEB::World::Tile]',
    is  => 'rw',
    default => undef,
));

before ('set_arg' => sub {
    my $self = shift;
    my $args = shift;
    my $l = $args->[0];
    my $x = $args->[1];
    my $y = $args->[2];
    $self->tile_from($l->at($x,$y));
});

has (tile => (
    isa => 'Maybe[TAEB::World::Tile]',
    is  => 'rw',
    default => undef,
));
sub set_additional_args {
    my $self = shift;
    $self->tile(shift);
}

sub check_possibility {
    my $self = shift;
    my $tme = shift;
    return unless $self->is_possible($tme);
    $self->add_possible_move($tme,undef);
}

sub is_possible { die "complex tactics must override is_possible"; }

use constant description => 'Moving to a nonadjacent square';

__PACKAGE__->meta->make_immutable;
no Moose;

1;
