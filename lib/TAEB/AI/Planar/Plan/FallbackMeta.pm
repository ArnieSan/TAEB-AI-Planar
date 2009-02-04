#!/usr/bin/env perl
package TAEB::AI::Planar::Plan::FallbackMeta;
use TAEB::OO;
use TAEB::Util qw/vi2delta/;
extends 'TAEB::AI::Planar::Plan';

# For fallback searches, we search tiles where we haven't been searching
# and which have at least 3 wall as adjacent neighbours.
sub is_search_blocked {
    my $self = shift;
    my $tile = shift;
    return (($tile->type eq 'wall') && !$tile->has_boulder);
}

sub spread_desirability {
    my $self = shift;
    my $level = TAEB->current_level;
    my $mines = $level->known_branch && $level->branch eq 'mines';
    # There are several possible reasons to fallback.
    # One common reason is that we're out of things to do.
    $level->each_tile(sub {
	my $tile = shift;
	# Be a lot more aggressive about searching, if we're in
	# fallback mode.
	if(!$mines && $tile->is_walkable(0) &&
	   scalar $tile->grep_adjacent(
	       sub {$self->is_search_blocked(shift)}) >= 3) {
	    $self->depends(1,"Search",$tile);
	}
	# Look under anything we can, whatever we're looking for
	# might be there.
	if($tile->is_interesting) {
	    $self->depends(1,"Investigate",$tile);
	}
    });
    # Another possible reason is that all non-fallback methods
    # apparently lead to certain death, generally due to a shortage of
    # hitpoints. That's what the CombatFallback metaplan is about.
    $self->depends(0.5,"CombatFallback");
}

use constant description => 'Trying a fallback strategy';
use constant references => ['Search','Investigate','CombatFallback'];

__PACKAGE__->meta->make_immutable;
no Moose;

1;
