#!/usr/bin/env perl
package TAEB::AI::Planar::Plan::ViaMimic;
use TAEB::OO;
use Moose;
extends 'TAEB::AI::Planar::Plan::Tactical';

has (tile => (
    isa => 'Maybe[TAEB::World::Tile]',
    is  => 'rw',
    default => undef,
));
sub set_additional_args {
    my $self = shift;
    $self->tile(shift);
}

sub calculate_risk {
    my $self = shift;
    my $tme  = shift;
    my $tile = $self->tile;
    $self->cost("Time",2);
    $self->cost("Hitpoints",20); # estimate for fighting a giant mimic
    $self->level_step_danger($tile->level); # is this accurate?
}

sub check_possibility_inner {
    my $self = shift;
    my $tme  = shift;
    my $tile = $self->tile;
    return unless $tile->has_boulder; # at least, looks like it does
    $self->add_possible_move($tme,$tile->x,$tile->y,$tile->level);
}

sub replaceable_with_travel { 0 }
sub action {
    my $self = shift;
    my $tile = $self->tile;
    return TAEB::Action->new_action('search', iterations => 1);
}

sub succeeded {
    my $self = shift;
    # We succeeded if we uncloaked a mimic.
    return $self->tile->glyph eq 'm';
}

use constant description => 'Waking a mimic so we can move past it';

__PACKAGE__->meta->make_immutable;
no Moose;

1;
