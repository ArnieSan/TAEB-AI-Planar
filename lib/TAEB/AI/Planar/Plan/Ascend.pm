#!/usr/bin/env perl
package TAEB::AI::Planar::Plan::Ascend;
use TAEB::OO;
use TAEB::Util qw/delta2vi/;
extends 'TAEB::AI::Planar::Plan::Strategic';

has _level => (
    isa => 'Maybe[TAEB::World::Level]',
    is  => 'rw',
);

sub aim_tile {
    shift->_level(TAEB->current_level);
    return @{TAEB->current_level->tiles_of('stairsup'), undef}[0];
}

sub has_reach_action { 1 }
sub reach_action {
    return TAEB::Action->new_action('ascend');
}
sub reach_action_succeeded {
    my $self = shift;
    # If we went upstairs, it worked.
    return TAEB->current_level != $self->_level;
}

sub calculate_extra_risk {
    my $self = shift;
    return $self->cost('Time', 1);
}

sub spread_desirability {
    # If we can't see the upstairs, explore to find it.
    my $self = shift;
    $self->depends(1,"ExploreHere");
}

use constant description => 'Going upstairs';
use constant references => ['ExploreHere'];

__PACKAGE__->meta->make_immutable;
no Moose;

1;
