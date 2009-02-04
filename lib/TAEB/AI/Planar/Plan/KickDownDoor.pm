#!/usr/bin/env perl
package TAEB::AI::Planar::Plan::KickDownDoor;
use TAEB::OO;
use TAEB::Util qw/delta2vi/;
extends 'TAEB::AI::Planar::Plan::Tactical';

# We take a tile (preferably with a door on) as argument.
has tile => (
    isa     => 'Maybe[TAEB::World::Tile]',
    default => undef,
);
sub set_additional_args {
    my $self = shift;
    $self->tile(shift);
}
sub action {
    my $self = shift;
    my $aim = $self->tile;
    my $dir = delta2vi($aim->x-TAEB->x,$aim->y-TAEB->y);
    return TAEB::Action->new_action('kick', direction => $dir);
}
sub check_possibility_inner {
    my $self = shift;
    my $tme  = shift;
    # If there is a closed door here, we can try to kick it down.
    # (Unless we have wounded legs or something like that, but that's
    # caught by generic impossibility checks; still worth adding here
    # when I get round to it as it'll probably speed the program up a
    # bit.)
    if ($self->tile->type ne 'closeddoor') {
	# Hmm... we can't try to open it, then.
	# This shouldn't have been called in the first place, but at
	# least we can use the opportunity to self-destruct.
	$self->validity(0);
	return;
    }
    # We can't actually kick the door down if we aren't standing next
    # to it (although again, why would this have been called in the
    # first place if that were the case?).
    if (abs($tme->{'tile_x'} - $self->tile->x) > 1
     || abs($tme->{'tile_y'} - $self->tile->y) > 1) {
	return;
    }
    # OK, this plan is possible, mark it as possible and calculate its
    # risk.
    $self->add_possible_move($tme, $self->tile->x, $self->tile->y);
}
sub succeeded {
    my $self = shift;
    # There's a very small chance this malfunctions if the door fails
    # to open and a xorn steps on it while we're trying to open it,
    # but that's unlikely to be a problem, especially as all it would
    # do would be to cause 3 attempts to open the door before we
    # realised it wouldn't work rather than 2. Besides, the xorn would
    # likely be more of an urgent problem to deal with than the door.
    # First, though, check to see if the tile's been reblessed.
    my $success;
    $self->tile($self->tile->level->at($self->tile->x,$self->tile->y));
    $success = $self->tile->type ne 'closeddoor';
    $success and $self->validity(0); # no longer a closed door here
    $success or TAEB->ai->try_again_step ==
	TAEB->step and $success = undef;
    return $success;
}
sub calculate_risk {
    my $self = shift;
    my $tile = $self->tile;
    return 0 unless $tile->type eq 'closeddoor'; # fail fast
    # A door is kicked down if rnl(35) is less than the average of
    # strength, dex and con. For now, don't allow for luck; then,
    # we can calculate the number of turns it'll take on average.
    # 0.693 here gives an approximation; it's the natural log of 2.
    # Also add 1 turn for the cost of stepping onto the tile itself.
    my $chance = (TAEB->dex + TAEB->con + TAEB->numeric_strength)/105;
    $self->cost('Time', 0.693/$chance + 1);
    $self->level_step_danger(TAEB->current_level);
    # Kicking a shop door is pretty expensive.
    $tile->is_shop and $self->cost('Zorkmids', 400);
}

use constant description => 'Kicking down a door';

__PACKAGE__->meta->make_immutable;
no Moose;

1;
