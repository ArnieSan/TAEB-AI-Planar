#!/usr/bin/env perl
package TAEB::AI::Planar::Plan::FallbackRest;
use TAEB::OO;
use Moose;
extends 'TAEB::AI::Planar::Plan::Strategic';

sub aim_tile {
    my $self = shift;
    return if TAEB->hp == TAEB->maxhp;
    return TAEB->current_tile;
}

sub has_reach_action { 1 }
sub reach_action {
    my $self = shift;
    return TAEB::Action->new_action('search', iterations => 5);
}

sub calculate_extra_risk { shift->aim_tile_turns(5); }

# This plan is always valid
sub invalidate { }

use constant description => 'Resting for HP because we have nothing better to do';

__PACKAGE__->meta->make_immutable;
no Moose;

1;
