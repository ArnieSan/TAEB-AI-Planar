#!/usr/bin/env perl
package TAEB::AI::Planar::Plan::Search;
use TAEB::OO;
use TAEB::Util qw/delta2vi vi2delta/;
use Moose;
extends 'TAEB::AI::Planar::Plan::Strategic';

# We take a tile as argument.
has (tile => (
    isa     => 'Maybe[TAEB::World::Tile]',
    is      => 'rw',
    default => undef,
));
sub set_arg {
    my $self = shift;
    $self->tile(shift);
}

sub aim_tile {
    my $self = shift;
    my $tile = $self->tile;
    $tile->grep_adjacent(sub {
	shift->searched < 20
    }) or return undef;
    return $tile;
}

sub has_reach_action { 1 }
sub reach_action {
    return TAEB::Action->new_action('search', iterations => 20);
}

sub calculate_extra_risk {
    my $self = shift;
    # The best possible searchability is a bit below 50; searchability
    # is measured in the same units as time (at least in Behavioral).
    # Therefore, we add a level_step_danger cost (/not/ aim_tile_turns)
    # of 50 minus the searchability.
    my $searchability = $self->tile_searchability;
#    TAEB->log->ai("Searchability of ".$self->tile." is $searchability");
    my $risk = $self->aim_tile_turns(20);
    # We search more searchable squares before less searchable squares,
    # always. This is a pure risk modifier, nothing to do with spending
    # plans.
    $risk += 100 * (100-$searchability);
    return $risk;
}
# TODO: This is a hack that a) doesn't work, and b) makes this hard to
# optimise. Probably it's best to leave this constant, and instead make
# code that /generates/ Search put a penalty in the desire multiplier.
# (Counting in terms of level_step_dangers in the risk is just ridiculous...)

sub is_search_blocked {
    my $self = shift;
    my $tile = shift;
    return (($tile->type eq 'rock' || $tile->type eq 'wall') &&
	    !$tile->has_boulder);
}

# Searchability; mostly using Behavioral's algorithm
sub tile_searchability {
    my $self = shift;
    my $tile = $self->tile;
    my $ai = TAEB->ai;
    my $pmap = $ai->plan_caches->{'Search'};
    if (!defined($pmap) || $pmap->{'aistep'} != $ai->aistep) {
        $pmap = {};
        $pmap->{'aistep'} = $ai->aistep;
        $pmap->{'map'} = find_empty_panels();
        $ai->plan_caches->{'Search'} = $pmap;
    }
    $pmap = $pmap->{'map'};
    return 50 if 3 == scalar $tile->grep_orthogonal(
        sub {$self->is_search_blocked(shift);});
    return searchability($pmap,$tile);
}

#####################################################################
# Some code blatantly stolen from Behavioral

sub find_empty_panels {
    my %pmap;

    for my $py (0 .. 3) {
        for my $px (0 .. 15) {
            $pmap{$px}{$py} = panel_empty(TAEB->current_level, $px, $py);
        }
    }

    return \%pmap;
}

sub panel_empty {
    my ($level, $px, $py) = @_;

    my $sx = ($px) * 5;
    my $sy = ($py) * 5 + 1;
    my $ex = ($px + 1) * 5 - 1;
    my $ey = ($py + 1) * 5;

    return 0 if ($px < 0 || $py < 0 || $px >= 20 || $py >= 4);
        # No sense searching the edge of the universe

    $ey = 21 if $ey == 20;

    for my $y ($sy .. $ey) {
        for my $x ($sx .. $ex) {
            my $tile = $level->at($x, $y);
            return 0 if !defined($tile) || $tile->type ne 'unexplored';
        }
    }

    return 1;
}

sub panel {
    my $tile = shift;

    my $panelx = int($tile->x / 5);
    my $panely = int(($tile->y - 1) / 5);

    $panely = 3 if $panely == 4;

    return ($panelx, $panely);
}

sub wall_interest {
    my ($pmap, $tile, $dir) = @_;

    return 0 unless $tile->type eq 'wall'
                 || $tile->type eq 'rock'
                 || $tile->type eq 'unexplored'; # just in case
    my $factor = 0.1;

    my ($px, $py) = panel($tile);
    my ($dx, $dy) = vi2delta($dir);

    if ($pmap->{$px + $dx}{$py + $dy}) {
        $factor = $tile->type eq 'wall' ? 6 : 1;
    }

    $factor -= $tile->searched*0.2;

    return (($factor > 0) ? $factor : 0);
}

sub searchability {
    my ($pmap, $tile) = @_;
    my $searchability = 0;

    # If the square is in an 5x5 panel, and is next to a 5x5 panel which
    # is empty, it is considered much more searchable.  This should focus
    # searching efforts on parts of the map that matter.

    my (%n, $pdir);

    # Don't search in shops, there's never anything to find and it can
    # cause pathing problems past shopkeepers
    return 0 if $tile->in_shop;

    # probably a bottleneck; we shall see

    $tile->each_adjacent(sub {
        $searchability += wall_interest($pmap, @_);
    });

    return $searchability;
}

#####################################################################

use constant description => 'Searching';

__PACKAGE__->meta->make_immutable;
no Moose;

1;
