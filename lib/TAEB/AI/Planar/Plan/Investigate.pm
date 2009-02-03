#!/usr/bin/env perl
package TAEB::AI::Plan::Investigate;
use TAEB::OO;
use TAEB::Util qw/delta2vi/;
use TAEB::Spoilers::Monster;
extends 'TAEB::AI::Plan::PathBased';

# We take a tile (preferably with a door on) as argument.
has tile => (
    isa     => 'Maybe[TAEB::World::Tile]',
    default => undef,
);
sub set_arg {
    my $self = shift;
    $self->tile(shift);
}

sub aim_tile {
    my $self = shift;
    my $tile = $self->tile;
    return $tile if $tile->is_interesting;
    $self->validity(0);
    return undef;
}

sub has_reach_action { 0 }

sub gain_resource_conversion_desire {
    # TODO: Work out from the symbol shown on the map, and possibly
    # farlook, the chance that this item is useful, and go gain a
    # bit of desire to investigate what it is.

    # Hack for the time being: investigate things shown as % or as $,
    # using a written-in value. (Incidentally, farlooking may be a
    # better option here, so long as we memorise the resulting values;
    # plans run at a farlook-safe time.)
    my $self = shift;
    my $glyph = $self->tile->glyph;
    my $ai = TAEB->personality;
    if ($glyph eq '$') {
	$ai->add_capped_desire($self, $ai->resources->{'Zorkmids'}->value
			       * 50);
    }
    if ($glyph eq '%') {
	$ai->add_capped_desire($self, $ai->resources->{'Nutrition'}->base_value
			       * 30);
    }
}

sub planspawn {
    my $self = shift;
    # If there's an interesting tile with a corpse on, create a
    # FloorFood plan for each possible corpse that might be on the
    # tile, to see if we'd want to eat it. The created FloorFood will
    # always plan-fail, but with Investigate as a dependency. (In
    # other words, if you know what's there, eat it; if you don't
    # know what's there but feel like eating it, investigate to see
    # if you want to eat it.)
    # Because we can't see what's there for certain, we use the list
    # of kill-times instead.
    my @kill_list = @{ $self->tile->kill_times };
    for my $killelement (@kill_list) {
	my $monster = $killelement->[0];
	# Don't bother investigating if the kill was so long ago that
	# the corpse will be rotten for certain by now.
	next if $killelement->[2] >= TAEB->turn - 100;
	my $spoiler = TAEB::Spoilers::Monster->monster($monster);
	TAEB->personality->get_plan("FloorFood",[$self->tile,$spoiler])
	    ->validate;
    }
}

use constant description => "Seeing what's on a tile";

__PACKAGE__->meta->make_immutable;
no Moose;

1;
