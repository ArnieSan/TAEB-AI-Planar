#!/usr/bin/env perl
package TAEB::AI::Planar::Plan::MoveTo;
use TAEB::OO;
use TAEB::Util 'refaddr';
use Tie::RefHash;
use TAEB::AI::Planar::TacticsMapEntry;
use TAEB::Spoilers::Sokoban;
use Moose;
extends 'TAEB::AI::Planar::Plan::Tactical';

# A metaplan. This one encompasses all methods of moving to a
# particular tile; it works by looking at the tile that's being moved
# to, then spawning an appropriate plan (or appropriate plans) to move
# there (such as OpenDoor+KickDownDoor, or Walk). This only allows for
# movement from adjacent tiles (as does the current tactical routing
# system in general). This metaplan is called by the AI to update the
# tactical info for a square.

# It's good to push a boulder onto a square if it has two or more
# adjacent squares which are adjacent to each other.
sub safe_boulder_square {
    my $tile = shift;
    my $ai = shift;
    my $tiletocountassafe = shift // $tile;
    my %xhash = ();
    my %yhash = ();
    $tile->each_orthogonal(sub {
        my $t = shift;
        $ai->tile_walkable($t,1) || $t == $tiletocountassafe
            and $xhash{$t->x}=1, $yhash{$t->y}=1;
    });
    return scalar keys %xhash > 1 && scalar keys %yhash > 1;
}

sub check_possibility {
    my $self = shift;
    my $tme  = shift;
    my $x    = $tme->{'tile_x'};
    my $y    = $tme->{'tile_y'};
    my $l    = $tme->{'tile_level'};
    my $tile = $l->at($x,$y);
    my $ai   = TAEB->ai;
    my $aistep = $ai->aistep;
    my $type = $tile->type;
    my $sokoban = defined $l->branch && $l->branch eq 'sokoban';

    if($type eq 'closeddoor') {
	# Open the door, or kick it down. Opening must be orthogonal
        # (actually, it needn't, but it needs to be orthogonal to walk
        # through it afterwards...), kicking down can be diagonal.
	$self->generate_plan($tme,"OpenDoor",'h');
	$self->generate_plan($tme,"OpenDoor",'j');
	$self->generate_plan($tme,"OpenDoor",'k');
	$self->generate_plan($tme,"OpenDoor",'l');
	$self->generate_plan($tme,"KickDownDoor",'s');
    }

    if($type eq 'opendoor') {
	# We can only Walk to it orthogonally.
	$self->generate_plan($tme,"Walk",'h');
	$self->generate_plan($tme,"Walk",'j');
	$self->generate_plan($tme,"Walk",'k');
	$self->generate_plan($tme,"Walk",'l');
    }

    # Boulders can sometimes be pushed. It depends on what's beyond them.
    # We try to push them if it's unexplored beyond them, and they aren't
    # on a safe square atm. We also may want to push a boulder which is
    # in a safe location, but only if specifically aiming there; so we use
    # PushBoulderRisky instead.
    if($tile->has_boulder && !$sokoban) {
        for my $bdir (['h',-1,0],['j',0,1],['k',0,-1],['l',1,0]) {
            my ($dir,$dx,$dy) = @$bdir;
            #D# TAEB->log->ai("Considering to push boulder");
            my $beyond = $l->at_safe($x+$dx,$y+$dy);
            my $plantype = (safe_boulder_square($tile, $ai) ?
                            "PushBoulderRisky" : "PushBoulder");
            if(defined $beyond and $beyond->type eq 'unexplored') {
                $self->generate_plan($tme,$plantype,$dir);
            }
            # If we can push the boulder to a square with two adjacent
            # neighbours, we can route round it from there. (Except in
            # Sokoban, but we shouldn't blindly push boulders there
            # anyway.) So continue moving beyond until we find either an
            # obstructed square, or a safely-pushable-to square; but don't
            # push a boulder if it's already on a safely-pushable-to
            # square (leave it unroutable instead). We use
            # is_inherently_unwalkable here; monsters can move, and are
            # often shown as I glyphs, so we want impossibility tracking
            # to track the monsters rather than assuming the boulder won't
            # move.
            while (defined $beyond && !$beyond->has_boulder &&
                   !$beyond->is_inherently_unwalkable(1,1) &&
                   !safe_boulder_square($beyond, $ai, $tile)) {
                $beyond = $l->at_safe($beyond->x+$dx,$beyond->y+$dy);
            }
            if(defined $beyond && !$beyond->has_boulder &&
               !$beyond->is_inherently_unwalkable(1,1)) {
                $self->generate_plan($tme,$plantype,$dir);
            }
        }
    }

    # We can just walk to passable tiles. There could be something blocking
    # them, but if so Walk should notice, and if it doesn't impossibility
    # tracking will. Obscured is on this list because it's worth a try, and
    # impossibility tracking will work out when it's impossible to route
    # there.
    if($type =~ /^(?:fountain|stairsup|stairsdown|ice|drawbridge|altar|
                     corridor|floor|grave|sink|throne|obscured)$/xo) {
	$self->generate_plan($tme,"Walk",'s');
    }
    # Unexplored tiles can be searched to explore them, if moving next
    # to them doesn't explore them (e.g. when blind). We shouldn't do
    # this unless they're adjacent to a stepped-on tile, though, as it
    # would be semantically wrong; generally speaking tiles become
    # explored when we walk next to them, and if tiles are more than
    # distance 1 away we don't yet know if they're unexplored.
    my $into_blindness;
    if($type eq 'unexplored' && TAEB->is_blind &&
       $tile->any_adjacent(sub{shift->stepped_on})) {
	$self->generate_plan($tme,"LightTheWay",'s');
	$into_blindness = 1;
    }
    # Certain traps are passable, at a cost.
    if($type eq 'trap') {
	$self->generate_plan($tme,"ThroughTrap",'s');
    }
    # In Sokoban, mimics are pathable by waking and killing them.
    if($sokoban && $tile->has_boulder &&
       !TAEB::Spoilers::Sokoban->probably_has_genuine_boulder($tile)) {
        $self->generate_plan($tme,"ViaMimic",'s');
    }
    # we want to path through unexplored because much of it will be rock
    # but if we're blind, we have no way of knowing when to stop digging (yet?)
    if($type eq 'rock' || ($type eq 'unexplored' && !$into_blindness) ||
	    $type eq 'wall' || $tile->has_boulder) {
	$self->generate_plan($tme,"Tunnel",'s');
    }
    # TODO: Need much more here
}

use constant references => ['OpenDoor','KickDownDoor','Walk','PushBoulder',
                            'PushBoulderRisky','LightTheWay','ThroughTrap',
                            'Tunnel','ViaMimic'];

__PACKAGE__->meta->make_immutable;
no Moose;

1;
