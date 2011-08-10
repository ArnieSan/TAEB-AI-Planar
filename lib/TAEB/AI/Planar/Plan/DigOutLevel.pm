#!/usr/bin/env perl
package TAEB::AI::Planar::Plan::DigOutLevel;
use TAEB::AI::Planar::Plan::ExploreLevel;
use TAEB::OO;
use Moose;
extends 'TAEB::AI::Planar::Plan';

# We take a level as argument.
has (level => (
    isa     => 'Maybe[TAEB::World::Level]',
    is      => 'rw',
    default => undef,
));

sub set_arg {
    my $self = shift;
    my $level = shift;
    $self->level($level);
}

sub spread_desirability {
    my $self = shift;
    my $level = $self->level;
    my $blind = TAEB->is_blind;
    my $ai = TAEB->ai;

    $level->each_tile(sub {
	my $tile = shift;
	$self->depends(1, "Investigate", $tile) unless $tile->explored;
    });
}

use constant description => 'Exploring a level *thorougly*';
use constant references => ['Investigate'];

__PACKAGE__->meta->make_immutable;
no Moose;

1;
