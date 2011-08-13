#!/usr/bin/env perl
package TAEB::AI::Planar::Plan::ViaMimic;
use TAEB::OO;
use Moose;
extends 'TAEB::AI::Planar::Plan::DirectionalTactic';
with 'TAEB::AI::Planar::Meta::Role::SqueezeChecked';

sub calculate_risk {
    my $self = shift;
    my $tme  = shift;
    my $tile = $self->tile($tme);
    $self->cost("Time",2);
    $self->cost("Hitpoints",20); # estimate for fighting a giant mimic
    $self->level_step_danger($tile->level); # is this accurate?
}

sub check_possibility {
    my $self = shift;
    my $tme  = shift;
    return unless $self->tile($tme)->has_boulder; # at least, looks like it does
    $self->add_directional_move($tme);
}

sub replaceable_with_travel { 0 }
sub action {
    my $self = shift;
    $self->tile; # memorize tile
    return TAEB::Action->new_action('search', iterations => 1);
}

sub succeeded {
    my $self = shift;
    # We succeeded if we uncloaked a mimic.
    return $self->memorized_tile->glyph eq 'm';
}

use constant description => 'Waking a mimic so we can move past it';

__PACKAGE__->meta->make_immutable;
no Moose;

1;
