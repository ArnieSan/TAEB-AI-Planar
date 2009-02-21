#!/usr/bin/env perl
package TAEB::AI::Planar::Plan::Strategic;
use TAEB::OO;
extends 'TAEB::AI::Planar::Plan';

# Go somewhere, do something. A base class for all the varied plans
# that work like that.

# Where we're aiming, a single tile. This subroutine returns the tile
# in question.
sub aim_tile {
    die 'A path-based plan has to path somewhere';
}
# What we plan to do when we get there, if anything.
sub has_reach_action { 0 }
sub reach_action {
    undef;
}

# Some plans need us to stop and perform the action one tile early,
# e.g. fighting a monster.
sub stop_early { 0 }

# Some plans have a mobile target. In such cases, we calculate risk
# one square at a time, because the target will probably be moving
# towards us.
sub mobile_target { 0 }

# Make sure the aim_tile is the same when calculating risk and when
# performing the action.
has _aim_tile_cache => (
    isa => 'Maybe[TAEB::World::Tile]',
    is  => 'rw',
);

# Risk. There is both cost and danger in pathing somewhere, but plans
# may often want to do something even costlier and more dangerous.
# Overriding calculate_extra_risk is the correct solution in that
# case.
sub calculate_extra_risk { 0 }
# Risk common to all path-based plans.
sub calculate_risk {
    my $self = shift;
    # We need to know where we're aiming, so that we can work out the
    # risk it costs to get there.
    my $aim = $self->aim_tile;
    my $ai  = TAEB->ai;
    if (!defined($aim)) {
	# We don't have anywhere to aim for, that's a plan
	# failure. Bail out.
	$self->_aim_tile_cache(undef);
	return 0;
    }
    if ($self->stop_early) {
	# Look for a tile next to the aim_tile that's cheap (or failing
	# that, possible) to path to.
	my $best_tile = undef;
	my $best_risk = 1e10;
	$aim->each_adjacent(sub {
	    my $tile = shift;
	    my $tme  = $ai->tme_from_tile($tile);
	    return unless defined $tme;
	    my $nr   = $tme->numerical_risk;
	    return unless $nr < $best_risk;
	    $best_risk = $nr;
	    $best_tile = $tile;
        });
	$aim = $best_tile;
	if (!defined($aim)) {
	    # We can't route where we're aiming. Bail out.
	    $self->_aim_tile_cache(undef);
	    return 0;
	}
    }
    $self->_aim_tile_cache($aim);
    my $risk = $self->calculate_extra_risk;
    if($aim == TAEB->current_tile) {
	# A special case; if we don't need to do any pathfinding,
	# the only risk is the extra risk of being on this square.
	return $risk;
    }
    my $target_tme = undef;
    if ($self->mobile_target) {
	my @chain = $ai->calculate_tme_chain($aim);
	@chain and $target_tme = $chain[0];
    } else {
	$target_tme = $ai->tme_from_tile($aim);
    }
    if (!defined $target_tme) {
	# We couldn't path there, this is a plan failure. Record the
	# risk as 0 so the failure's consequences are immediately
	# recognised.
	return 0;
    }
    # Grab the total risk from the last TME in the chain.
    $risk += $self->cost_from_tme($target_tme);
    # Before returning the risk, spread risk-reduction dependencies.
    for my $planname (keys %{$target_tme->{'make_safer_plans'}}) {
	my $plan = $ai->plans->{$planname};
	my $amount = $target_tme->{'make_safer_plans'}->{$planname};
	if(!defined $plan) {
	    TAEB->log->ai("Plan $planname has gone missing...");
	    next;
	}
	#$self->desire < $amount and $amount = $self->desire;
	## START DEBUG CODE
# 	TAEB->log->ai("Spreading $amount desire to msp $planname...");
# 	my $thme = $ai->threat_map->{$target_tme->{tile_level}}->
# 	    [$target_tme->{tile_x}]->[$target_tme->{tile_y}];
# 	for my $p (keys %$thme) {
# 	    defined($thme->{$p}) or next;
# 	    my ($turns, $reductionplan) = split / /, $p;
# 	    my @costs = %{$thme->{$p}};
# 	    local $" = ';';
# 	    TAEB->log->ai("THME has plan $reductionplan after $turns ".
# 				   "saving @costs");
# 	}
	## END DEBUG CODE
	push @{$plan->reverse_dependencies}, $self;
	$ai->add_capped_desire($plan, $self->desire);
    }
    return $risk;
}
# Used in calculate_extra_risk; this represents the cost of spending
# the given number of turns on the aim_tile. This returns a low value
# normally, because monsters will have more time to catch up to the
# square while we path there; it will be completely accurate when on
# the tile itself.
sub aim_tile_turns {
    my $self = shift;
    my $turns = shift;
    my $aim = $self->_aim_tile_cache;
    my $ai = TAEB->ai;
    my $thme = $ai->threat_map->{$aim->level}->[$aim->x]->[$aim->y];
    my %resamounts = ('Time' => $turns);
    my $cost = 0;
    for my $p (keys %$thme) {
	defined($thme->{$p}) or next;
	my ($thmeturns) = split / /, $p;
	next if $thmeturns > $turns;
	my %costs = %{$thme->{$p}};
	for my $resource (keys %costs) {
	    $resamounts{$resource} += $costs{$resource} * ($turns - $thmeturns);
	}
    }
    for my $resource (keys %resamounts) {
	$cost += $self->cost($resource, $resamounts{$resource});
    }
    return $cost;
}

# Trying this plan. We follow the path if there is one, else perform
# the action if we're where we want to be, else bail.
sub action {
    my $self = shift;
    my $ai   = TAEB->ai;
    return undef unless defined $self->_aim_tile_cache;
    # Yes, return the reach action even if there isn't one. It's undef
    # in that case, which is exactly what we want; it's an error to
    # try to path somewhere if we're already there, we should try a
    # different plan instead.
    return $self->reach_action
	if TAEB->current_tile == $self->_aim_tile_cache;
    my @chain = $ai->calculate_tme_chain($self->_aim_tile_cache);
    return undef unless @chain;
    # We want the first step in the chain.
    return $chain[0]->{'tactic'};
}

# Whether we succeeded. This is called with the tactic as an argument
# if the tactic succeeded, or with undef as argument if it wasn't
# based on a tactic.
sub succeeded {
    my $self = shift;
    if (defined(shift)) {
	return 1 if $self->_aim_tile_cache == TAEB->current_tile;
	return undef;
    }
    return 1 unless $self->has_reach_action;
    return $self->reach_action_succeeded;
}
# Whether the reach action succeeded.
sub reach_action_succeeded { 1 };

__PACKAGE__->meta->make_immutable;
no Moose;

1;
