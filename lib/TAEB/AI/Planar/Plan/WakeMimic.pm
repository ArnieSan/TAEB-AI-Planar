#!/usr/bin/env perl
package TAEB::AI::Planar::Plan::WakeMimic;
use TAEB::OO;
extends 'TAEB::AI::Planar::Plan::Strategic';

# We take a tile as argument.
has tile => (
    isa     => 'Maybe[TAEB::World::Tile]',
    is      => 'rw',
    default => undef,
);
sub set_arg {
    my $self = shift;
    $self->tile(shift);
}

sub aim_tile {
    my $self = shift;
    my $tile = $self->tile;
    return $tile;
}

sub stop_early { 1 }
sub has_reach_action { 1 }
sub reach_action {
    return TAEB::Action->new_action('search', iterations => 1);
}

sub calculate_extra_risk {
    my $self = shift;
    my $risk = $self->cost('Time' => 1);
    return $risk;
}
sub reach_action_succeeded {
    my $self = shift;
    my $ai = TAEB->ai;
    # Tell SolveSokoban we've woken/failed to wake the mimic.
    $ai->get_plan("SolveSokoban")->mimictile(undef);
    # If we can now see the mimic, it worked.
    return $self->tile->glyph eq 'm';
}

use constant description => 'Waking a probable mimic';

__PACKAGE__->meta->make_immutable;
no Moose;

1;
