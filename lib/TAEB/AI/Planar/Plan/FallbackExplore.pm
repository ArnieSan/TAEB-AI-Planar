#!/usr/bin/env perl
package TAEB::AI::Planar::Plan::FallbackExplore;
use TAEB::AI::Planar::Plan::ExploreLevel;
use TAEB::OO;
extends 'TAEB::AI::Planar::Plan';

# We take a level as argument.
has level => (
    isa     => 'Maybe[TAEB::World::Level]',
    is      => 'rw',
    default => undef,
);
sub set_arg {
    my $self = shift;
    my $level = shift;
    $self->level($level);
}

sub spread_desirability {
    my $self = shift;
    my $level = $self->level;
    my $mines = $level->known_branch && $level->branch eq 'mines'
        && !$level->is_minetown;
    my $blind = TAEB->is_blind;
    $level->each_tile(sub {
	my $tile = shift;
	if($tile->is_walkable(0,1)) {
	   my $orthogonals = scalar $tile->grep_orthogonal(
	       sub {TAEB::AI::Planar::Plan::ExploreLevel
                        ->is_search_blocked(shift)});
           ($orthogonals == 1 || $orthogonals == 2) and
               $self->depends($mines ? 0.7 : 1, "Search", $tile);
        }
    });
}

use constant description => 'Exploring a level thoroughly';
use constant references => ['Search'];

__PACKAGE__->meta->make_immutable;
no Moose;

1;
