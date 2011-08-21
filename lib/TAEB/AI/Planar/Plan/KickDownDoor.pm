#!/usr/bin/env perl
package TAEB::AI::Planar::Plan::KickDownDoor;
use TAEB::OO;
use TAEB::Util qw/delta2vi/;
use Moose;
extends 'TAEB::AI::Planar::Plan::DirectionalTactic';
with 'TAEB::AI::Planar::Meta::Role::SqueezeChecked';

use constant door_action => 'kick';
use constant chance_factor => 105;

sub action {
    my $self = shift;
    $self->tile; # memorize location
    return TAEB::Action->new_action($self->door_action, direction => $self->dir);
}
sub check_possibility {
    my $self = shift;
    my $tme  = shift;
    my $tile = $self->tile($tme);
    # If there is a closed door here, we can try to kick it down.
    # (Unless we have wounded legs or something like that, but that's
    # caught by generic impossibility checks; still worth adding here
    # when I get round to it as it'll probably speed the program up a
    # bit.)
    if ($tile->type ne 'closeddoor') {
	# Hmm... we can't try to open it, then.
	# This shouldn't have been called in the first place, but at
	# least we can use the opportunity to self-destruct.
	$self->validity(0);
	return;
    }
    # We can't open a locked door.
    $tile->is_locked and $self->door_action eq 'open' and return;
    # OK, this plan is possible, mark it as possible and calculate its
    # risk.
    $self->add_directional_move($tme, $tile->x, $tile->y);
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
    my $tile = $self->memorized_tile->level->at(
        $self->memorized_tile->x,$self->memorized_tile->y);
    $success = $tile->type ne 'closeddoor';
    $success and $self->validity(0); # no longer a closed door here
    $success or TAEB->ai->try_again_step ==
	TAEB->step and $success = undef;
    return $success;
}
sub special_door_risk {
    my $self = shift;
    my $tile = shift;
    # Don't kick down shop doors.
    $tile->is_shop || $tile->in_shop ||
        $tile->any_adjacent(sub {$_->in_shop})
        and $self->cost('Impossibility', 1);
    # Kicking down doors in the Mines is /incredibly/ dangerous,
    # because it means we're in Minetown and the watch and the
    # shopkeepers will want to kill us.
    # (TODO: It could also mean we're in Mine's End, where it's less
    # dangerous.)
    my $level = $tile->level;
    my $mines = $level->known_branch && $level->branch eq 'mines';
    $mines and $self->cost('Impossibility', 1);
}
sub calculate_risk {
    my $self = shift;
    my $tme  = shift;
    my $tile = $self->tile($tme);
    return 0 unless $tile->type eq 'closeddoor'; # fail fast
    # A door is kicked down if an rnl() result is less than the
    # average of strength, dex and con. For now, don't allow for luck;
    # then, we can calculate the number of turns it'll take on
    # average. 0.693 here gives an approximation; it's the natural log
    # of 2. Also add 1 turn for the cost of stepping onto the tile
    # itself.
    my $chance = (TAEB->dex + TAEB->con + TAEB->numeric_strength)/
        $self->chance_factor;
    $self->cost('Time', 0.693/$chance + 1);
    $self->level_step_danger(TAEB->current_level);
    $self->special_door_risk($tile);
}

use constant description => 'Kicking down a door';

__PACKAGE__->meta->make_immutable;
no Moose;

1;
