#!/usr/bin/env perl
package TAEB::AI::Planar::Plan::ThroughTrap;
use TAEB::OO;
use TAEB::Util qw/delta2vi/;
extends 'TAEB::AI::Planar::Plan::Tactical';

# Traps that we can route through, but at an additional cost in resources.
# This uses /maximum/ damage for traps; we want to be very cautious around
# them.
use constant trap_costs => {
    'pit' => {'Time' => 8, 'Hitpoints' => 6}, # 6 + d2 turns, d6 damage
    'spiked pit' => {'Time' => 8, 'Hitpoints' => 10}, # d10 damage
    # spiked pits also have a 1-in-10 chance of str poison 8
    'arrow trap' => {'Hitpoints' => 6},
    'dart trap' => {'Hitpoints' => 3}, # and a 1-in-6 chance of con poison 10r
    'falling rock trap' => {'Hitpoints' => 12}, # 2d6, or 2 if you have a helmet
    'squeaky board' => {}, # does nothing but wake monsters
    'bear trap' => {'Time' => 8}, # 4 + d4 turns
    'sleeping gas trap' => {'Time' => 25}, # d25 turns; TODO: Helpless for this
    'web' => {'Time' => 2}, # actually Str-dependent
    'anti-magic field' => {}, # TODO: Pw loss equal to your level
    'land mine' => {'Time' => 8, 'Hitpoints' => 22}, # d16 + pit effects
    'rolling boulder trap' => {'Hitpoints' => 26}, # max thrown boulder damage
    # magic portals should only be routed through deliberately
    # rust trap not coded for yet; it erodes things
    # hole, trapdoor, tele, level tele are unroutable
    # polytrap not worth ever routing through, that's too risky
};

has tile => (
    isa => 'Maybe[TAEB::World::Tile]',
    is  => 'rw',
    default => undef,
);
sub set_additional_args {
    my $self = shift;
    $self->tile(shift);
}

sub calculate_risk {
    my $self = shift;
    my $tme  = shift;
    my $tile = $self->tile;
    my $extra_costs = trap_costs->{$tile->trap_type};
    $self->cost("Time",1);
    $self->cost($_,$extra_costs->{$_}) for keys %$extra_costs;
    $self->level_step_danger($tile->level); # is this accurate?
}

sub check_possibility_inner {
    my $self = shift;
    my $tme  = shift;
    my $tile = $self->tile;
    return if $tile->type ne 'trap';
    if (defined $tile->monster) {
	# We need to generate a plan to scare the monster out of the
	# way, if the AI doesn't want to kill it for some reason. Yes,
	# even if there's a trap on the same square.
	$self->generate_plan($tme,"ScareMonster",$tile);
	return;
    }
    return unless $tile->is_walkable; # avoid traps in Sokoban
    return unless defined trap_costs->{$tile->trap_type};
    $self->add_possible_move($tme,$tile->x,$tile->y,$tile->level);
}

sub replaceable_with_travel { 0 }
sub action {
    my $self = shift;
    my $tile = $self->tile;
    my $dir = delta2vi($tile->x - TAEB->x, $tile->y - TAEB->y);
    if (!defined $dir) {
	die "Could not move from ".TAEB->x.", ".TAEB->y." to ".
	    $tile->x.", ".$tile->y." because they aren't adjacent.";
    }
    return TAEB::Action->new_action(
	'move', direction => $dir);
}

sub succeeded {
    my $self = shift;
    return TAEB->current_tile == $self->tile;
}

use constant description => 'Walking through a trap';
use constant references => ['ScareMonster'];

__PACKAGE__->meta->make_immutable;
no Moose;

1;
