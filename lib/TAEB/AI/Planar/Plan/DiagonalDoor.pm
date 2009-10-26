#!/usr/bin/env perl
package TAEB::AI::Planar::Plan::DiagonalDoor;
use TAEB::OO;
use TAEB::Util qw/delta2vi/;
extends 'TAEB::AI::Planar::Plan::Tactical';

has tile => (
    isa => 'Maybe[TAEB::World::Tile]',
    is  => 'rw',
    default => undef,
);
has door => (
    isa => 'Maybe[TAEB::World::Tile]',
    is  => 'rw',
    default => undef,
);
has wasclosed => (
    isa => 'Bool',
    is  => 'rw',
    default => 0,
);
sub set_additional_args {
    my $self = shift;
    $self->tile(shift);
    $self->door(undef);
}

# We store the location where the door ought to be as soon as we get
# a TME that we can use to find out where we're moving from. (The TME
# is never stored in any plan for efficiency reasons, which makes
# coding somewhat more interesting.)
sub locate_door {
    my $self = shift;
    my $tme = shift;
    my $door = $self->door;
    defined $door and return $door;
    my $tile = $self->tile;
    my $dx = 0;
    my $dy = 0;
    $tile->x-2 == $tme->{'tile_x'} and $dx = -1;
    $tile->x+2 == $tme->{'tile_x'} and $dx =  1;
    $tile->y-2 == $tme->{'tile_y'} and $dy = -1;
    $tile->y+2 == $tme->{'tile_y'} and $dy =  1;
    $dx or $dy or die "Can't tell where to look for the door";
    $door = $tile->level->at($tme->{'tile_x'}-$dx,$tme->{'tile_y'}-$dy);
    $self->door($door);
    return $door;
}

sub calculate_risk {
    my $self = shift;
    my $tme  = shift;
    my $tile = $self->tile;
    my $door = $self->locate_door($tme);
    # The chance of closing a door in one try is the same as the chance
    # of opening it in one try. Kicking down a door is harder.
    my $openchance = (TAEB->dex + TAEB->con + TAEB->numeric_strength)/60;
    my $kickchance = (TAEB->dex + TAEB->con + TAEB->numeric_strength)/105;
    $self->cost("Time", 0.693/$kickchance + 2);
    $self->cost("Time", 0.693/$openchance) if $door->type eq 'opendoor';
    $self->level_step_danger($tile->level);
    $self->level_step_danger($tile->level);
    $self->level_step_danger($tile->level) if $door->type eq 'opendoor';
    $door->type eq 'closeddoor' and $door->is_shop
	and $self->cost('Zorkmids', 400);
    $tile->in_shop and $self->cost('Zorkmids', 400);
    $tile->level->at($tme->{'tile_x'}, $tme->{'tile_y'})->in_shop
        and $self->cost('Zorkmids', 400);
    my $level = TAEB->current_level;
    my $mines = $level->known_branch && $level->branch eq 'mines';
    $mines and $self->cost('Hitpoints', 150);
}

sub check_possibility_inner {
    my $self = shift;
    my $tme  = shift;
    my $tile = $self->tile;
    my $ai   = TAEB->ai;
    return unless $ai->tile_walkable($tile);
    my $door = $self->locate_door($tme);
    return if defined $door->monster;
    return unless $door->type eq 'opendoor' || $door->type eq 'closeddoor';
    $self->wasclosed($door->type eq 'closeddoor');
    $self->add_possible_move($tme,$tile->x,$tile->y,$tile->level);
}

sub action {
    my $self = shift;
    my $tile = $self->door;
    my $dir = delta2vi($tile->x - TAEB->x, $tile->y - TAEB->y);
    return TAEB::Action->new_action('kick', direction => $dir)
	if $tile->type eq 'closeddoor';
    return TAEB::Action->new_action('close', direction => $dir)
	if $tile->type eq 'opendoor';
    return undef;
}

sub succeeded {
    my $self = shift;
    # This is complex. If there's no door where we're aiming, we
    # succeeded. If there's a closed door, then we return undef if
    # there wasn't a closed door before or if we're on a try-again
    # step (i.e. 'WHAMMM!'). If there's an open door, we return undef
    # only if we're on a try-again step ('The door resists.'). If none
    # of these cases hold, something went wrong; we return 0.
    my $door = $self->door;
    TAEB->ai->try_again_step == TAEB->step and return undef;
    $door->type eq 'opendoor' and return 0;
    $door->type eq 'closeddoor' and $self->wasclosed and return 0;
    $door->type eq 'closeddoor' and return undef;
    $door->type eq 'obscured' and return 0; # something got stuck in the door
    return 1;
}

use constant description => 'Clearing a doorway';

__PACKAGE__->meta->make_immutable;
no Moose;

1;
