#!/usr/bin/env perl
package TAEB::AI::Planar::Plan::Search;
use TAEB::OO;
use TAEB::Util qw/delta2vi/;
extends 'TAEB::AI::Planar::Plan::PathBased';

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
    $tile->searched >= 20 and return undef;
    return $tile;
}

sub has_reach_action { 1 }
sub reach_action {
    return TAEB::Action->new_action('search', iterations => 20);
}

sub calculate_extra_risk {
    my $self = shift;
    # For each time the aim_tile's been searched, we add 1 turn of
    # risk to the total (in addition to pathing risk and the risk for
    # the time it takes to search). This reflects the risk that we
    # don't find anything and so have a less desirable search than
    # expected.
    my $risk = $self->aim_tile_turns($self->tile->searched+20);
    return $risk;
}

use constant description => 'Searching';

__PACKAGE__->meta->make_immutable;
no Moose;

1;
