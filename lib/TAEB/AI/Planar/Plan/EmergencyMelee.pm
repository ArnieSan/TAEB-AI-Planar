#!/usr/bin/env perl
package TAEB::AI::Planar::Plan::EmergencyMelee;
use TAEB::OO;
use TAEB::Util qw/delta2vi/;
use Moose;
extends 'TAEB::AI::Planar::Plan::Strategic';

sub aim_tile {
    my $self = shift;
    return TAEB->current_tile;
}

sub has_reach_action { 1 }
sub reach_action {
    my $self = shift;
    my $tile = TAEB->current_tile;
    my @monstertiles = $tile->grep_adjacent(sub {
        $_->has_monster && ($_->monster->disposition // 'hostile') eq 'hostile' &&
            !$_->monster->respects_elbereth});
    return TAEB::Action->new_action('melee', direction =>
        delta2vi($monstertiles[0]->x-TAEB->x,$monstertiles[0]->y-TAEB->y))
        if @monstertiles;
    @monstertiles = $tile->grep_adjacent(sub {
        $_->has_monster && ($_->monster->disposition // 'hostile') eq 'hostile'});
    return undef unless @monstertiles;
    return TAEB::Action->new_action('melee', direction =>
        delta2vi($monstertiles[0]->x-TAEB->x,$monstertiles[0]->y-TAEB->y));
}

# No aim_tile_turns! This only happens in an emergency, so we want to
# completely ignore threats.
sub calculate_extra_risk {
    my $self = shift;
    return $self->cost("Time",1) + $self->cost("Pacifism",1);
}

sub reach_action_succeeded {
    # Reinstate all plans. This is because they'll have been abandoned
    # in order to do the emergency Elberething.
    my $self = shift;
    my $ai = TAEB->ai;
    $ai->tactical_success_count($ai->tactical_success_count + 10000);
    $ai->strategic_success_count($ai->strategic_success_count + 10000);
    return 1; # if we're still alive, it worked
}

use constant description => "Meleeing an adjacent monster as a last resort";

__PACKAGE__->meta->make_immutable;
no Moose;

1;
