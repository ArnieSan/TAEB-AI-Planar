#!/usr/bin/env perl
package TAEB::AI::Planar::Plan::DefensiveElbereth;
use TAEB::OO;
use TAEB::Util qw/delta2vi/;
extends 'TAEB::AI::Planar::Plan::Strategic';

sub aim_tile {
    my $self = shift;
    my $ecount = TAEB->current_tile->elbereths;
    return undef
        if $ecount >= 3
        || ($ecount >= 1 && TAEB->current_tile->engraving_type eq 'burned');
    return undef unless TAEB->can_engrave;
    return TAEB->current_tile;
}

sub writes_elbereth { 1 }
sub has_reach_action { 1 }
sub reach_action {
    my $self = shift;
    return TAEB::Action->new_action('engrave');
}

sub calculate_extra_risk {
    my $self = shift;
    my $risk = 0;
    # Very approximate estimated time to dust three Elbereths at once
    $risk += $self->aim_tile_turns(5);
    # Be less cautious when on high health; this is a penalty cost to
    # mean that this action tends to be avoided when hardly injured.
    if (TAEB->maxhp * 3.0/4 < TAEB->hp) {
        $risk += $self->cost(
            'Hitpoints',TAEB->hp - (TAEB->maxhp * 3.0/4));
    }
    return $risk;
}

sub spread_desirability {
    my $self = shift;
    my $ecount = TAEB->current_tile->elbereths;
    $self->depends(0.5,"FallbackRest")
        if $ecount >= 3
        || ($ecount >= 1 && TAEB->current_tile->engraving_type eq 'burned');
}

use constant description => "Elberething to make things safer";
use constant references => ['FallbackRest'];

__PACKAGE__->meta->make_immutable;
no Moose;

1;
