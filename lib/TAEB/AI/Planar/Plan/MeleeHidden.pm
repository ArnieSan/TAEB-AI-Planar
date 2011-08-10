#!/usr/bin/env perl
package TAEB::AI::Planar::Plan::MeleeHidden;
use TAEB::OO;
use TAEB::Util qw/delta2vi/;
use Moose;
extends 'TAEB::AI::Planar::Plan::Strategic';

# We take a tile as argument.
has (tile => (
    isa     => 'Maybe[TAEB::World::Tile]',
    is  => 'rw',
    default => undef,
));
sub set_arg {
    my $self = shift;
    $self->tile(shift);
}

# When meleeing, we run up next to the monster before attacking.
sub aim_tile {
    shift->tile;
}
sub stop_early { 1 }
sub mobile_target { 1 }
# Whack it!
sub has_reach_action { 1 }
sub reach_action {
    my $self = shift;
    my $aim = $self->aim_tile;
    my $dir = delta2vi($aim->x-TAEB->x,$aim->y-TAEB->y);
    return undef unless $dir =~ /[yuhjklbn]/;
    return TAEB::Action->new_action('melee', direction => $dir);
}

sub calculate_extra_risk {
    my $self = shift;
    # TODO: Risk from whatever monster we think is on the square
    return $self->aim_tile_turns(1) + $self->cost("Pacifism",1);
}

# Invalidate ourselves if the monster stops existing.
sub invalidate { shift->validity(0); }

use constant description => 'Meleeing an expected hidden monster';

__PACKAGE__->meta->make_immutable;
no Moose;

1;
