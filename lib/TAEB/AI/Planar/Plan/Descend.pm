#!/usr/bin/env perl
package TAEB::AI::Planar::Plan::Descend;
use TAEB::OO;
use TAEB::Util qw/delta2vi/;
extends 'TAEB::AI::Planar::Plan::Strategic';

has _level => (
    isa => 'Maybe[TAEB::World::Level]',
    is  => 'rw',
);

sub aim_tile {
    shift->_level(TAEB->current_level);
    return TAEB->current_level->first_tile(sub {shift->type eq 'stairsdown'});
}

sub has_reach_action { 1 }
sub reach_action {
    return TAEB::Action->new_action('descend');
}
sub reach_action_succeeded {
    my $self = shift;
    # If we went downstairs, it worked.
    return TAEB->current_level != $self->_level;
}

sub calculate_extra_risk {
    my $self = shift;
    return $self->cost('Time', 1);
}

sub spread_desirability {
    # If we can't see the downstairs, explore to find it.
    my $self = shift;
    $self->depends(1,"ImproveConnectivity");
}

use constant description => 'Going downstairs';
use constant references => ['ImproveConnectivity'];

__PACKAGE__->meta->make_immutable;
no Moose;

1;
