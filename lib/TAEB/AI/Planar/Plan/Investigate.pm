#!/usr/bin/env perl
package TAEB::AI::Planar::Plan::Investigate;
use TAEB::OO;
use TAEB::Util qw/delta2vi/;
use TAEB::Spoilers::Monster;
extends 'TAEB::AI::Planar::Plan::Strategic';

# We take a tile (preferably with a door on) as argument.
has tile => (
    isa     => 'Maybe[TAEB::World::Tile]',
    is  => 'rw',
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

sub invalidate { shift->validity(0); }

sub gain_resource_conversion_desire {
    # TODO: Work out from the symbol shown on the map, and possibly
    # farlook, the chance that this item is useful, and go gain a
    # bit of desire to investigate what it is.

    # Hack for the time being: investigate things shown as % ) or $,
    # using a written-in value. (Incidentally, farlooking may be a
    # better option here, so long as we memorise the resulting values;
    # plans run at a farlook-safe time.)
    my $self = shift;
    my $glyph = $self->tile->glyph;
    my $mines = $self->tile->known_branch && $self->tile->branch eq 'mines';
    my $ai = TAEB->ai;
    if ($glyph eq '$') {
	$ai->add_capped_desire($self, $ai->resources->{'Zorkmids'}->value
			       * 500);
    }
    if ($glyph eq '[') {
	$ai->add_capped_desire($self, $ai->resources->{'AC'}->value
			       * 4);
    }
    if ($glyph eq '%') {
	# This is probably a fresh corpse, let's assume it had juicy loot
	$ai->add_capped_desire($self,
	    $ai->resources->{'Nutrition'}->base_value * 30 +
	    $ai->resources->{'AC'}->value * 4 +
	    $ai->resources->{'Ammo'}->value * 5 +
	    $ai->resources->{'DamagePotential'}->value * 1);
    }
    # Interesting tiles without a glyph only happen if we throw things at them.
    if ($glyph eq ')' || $glyph eq '.' || ($glyph eq '#' && !$mines)) {
        $ai->add_capped_desire($self, $ai->resources->{'Ammo'}->base_value);
    }
}

use constant description => "Seeing what's on a tile";
use constant references => [];

__PACKAGE__->meta->make_immutable;
no Moose;

1;
