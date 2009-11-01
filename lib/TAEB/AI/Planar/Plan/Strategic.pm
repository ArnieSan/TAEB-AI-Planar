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

# Does this plan involve writing Elbereth on a square that previously
# didn't have one?
sub writes_elbereth { 0 }

# Some plans need us to stop and perform the action one tile early,
# e.g. fighting a monster. This is 0 to move to the tile, 1 to move
# next to the tile, and higher numbers for progressively higher
# ranges (orthogonal/diagonal only, though).
sub stop_early { 0 }
# What blocks an orthogonal/diagonal stop_early ray. This is given
# a tile as argument, and should return 1 if it blocks, 0 if it
# doesn't.
sub stop_early_blocked_by { 0 }

# Some plans have a mobile target. In such cases, we calculate risk
# one square at a time, because the target will probably be moving
# towards us.
sub mobile_target { 0 }

# Make sure the aim_tile is the same when calculating risk and when
# performing the action.
has aim_tile_cache => (
    isa => 'Maybe[TAEB::World::Tile]',
    is  => 'rw',
);
has used_travel_to => (
    isa => 'Maybe[TAEB::World::Tile]',
    is  => 'rw',
);

# Calculating how good Elberething is
has elbereth_saves => (
    isa => 'Num',
    is  => 'rw',
    default => 0,
);

# Extra make_safer_plans for long plans. This is a ref of their names.
has extra_msp => (
    isa => 'ArrayRef[Str]',
    is => 'rw',
    default => sub { [] },
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
    my $tct = TAEB->current_tile;
    if (!defined($aim)) {
	# We don't have anywhere to aim for, that's a plan
	# failure. Bail out.
	$self->aim_tile_cache(undef);
	return 0;
    }
    if ($self->stop_early) {
	# Look for a tile next to the aim_tile that's cheap (or failing
	# that, possible) to path to.
	my $best_tile = undef;
	my $best_risk = 1e12;
        DIRECTION: for my $delta (qw/y u h j k l b n/) {
	    my $tile = $aim;
            my $range = 0;
            while (++$range <= $self->stop_early) {
                $tile = $tile->at_direction($delta);
                next DIRECTION unless defined $tile;
                next DIRECTION if $self->stop_early_blocked_by($tile);
                my $tme = $ai->tme_from_tile($tile);
                next unless defined $tme;
                my $nr = $tme->numerical_risk;
                next unless $nr < $best_risk;
                $best_risk = $nr;
                $best_tile = $tile;
            }
        }
	$aim = $best_tile;
	if (!defined($aim)) {
	    # We can't route where we're aiming. Bail out.
	    $self->aim_tile_cache(undef);
	    return 0;
	}
    }
    $self->aim_tile_cache($aim);
    $self->elbereth_saves(0);
    my $risk = $self->calculate_extra_risk;
    my $target_tme = undef;
    if ($self->mobile_target && $tct != $aim) {
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
#    TAEB->log->ai("Checking risk reductions for $self...");
    # Before returning the risk, spread risk-reduction dependencies.
    for my $planname ('DefensiveElbereth', (@{$self->extra_msp}),
                      (keys %{$target_tme->{'make_safer_plans'}})) {
	my $plan;
	my $amount;
        if ($planname eq 'DefensiveElbereth') {
            $amount = $self->elbereth_saves;
            next if $tct != $aim;
            next if $self->writes_elbereth; # no recursive Elberething!
            next unless $amount;
            $plan = $ai->get_plan('DefensiveElbereth');
        } else {
            $plan = $ai->plans->{$planname};
            $amount = $target_tme->{'make_safer_plans'}->{$planname};
        }
	if (!defined $plan) {
            # TODO: Figure out why this happens. I /think/ it's because
            # the plan refers to a TME on another level which refers to
            # a monster that's no longer in memory, but I'm not sure.
	    TAEB->log->ai("Plan $planname has gone missing...");
            next;
	}
	$self->desire < $amount and $amount = $self->desire;
	## START DEBUG CODE
# 	TAEB->log->ai("Spreading desire to msp $planname...");
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
	$plan->reverse_dependencies->{$self} = $self;
        if($planname eq 'DefensiveElbereth')
        {
            $ai->add_capped_desire($plan, $amount);
        } else {
            $ai->add_capped_desire($plan, $self->desire);
        }
	# This needs to run before the plan calculates risk in order to
	# have any effect. Therefore, if the plan's been calculated
        # already (say this is a msp for the other plan as well in a
        # cyclic relationship, and it ran first), we have to recalculate.
        # NB INVARIANT
        if($plan->in_make_safer_on_step < $ai->aistep) {
            $plan->in_make_safer_on_step($ai->aistep);
            if($plan->risk_valid_on_step == $ai->aistep) {
                $plan->risk_valid_on_step(-1);
                # Luckily, we know how desirable the plan was first time
                # round, if its risk has already been calculated.
                $ai->add_capped_desire($plan,$plan->desire);
            }
        }
        $self->add_dependency_path($plan);
    }
    if($aim == $tct) {
	# A special case; if we don't need to do any pathfinding,
	# the only risk is the extra risk of being on this square.
	return $risk;
    }
    # Grab the total risk from the last TME in the chain.  If we're not
    # dealing with the problem, penalize according to analysis_window.
    $risk += $self->cost_from_tme($target_tme) *
	($self->in_make_safer_on_step == $ai->aistep
		? 1 : $ai->analysis_window);
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
    my $aim = $self->aim_tile_cache;
    my $ai = TAEB->ai;
    my $resources = $ai->resources;
    my $alevel = $aim->level;
    my $tlevel = TAEB->current_level;
    my $thme = $ai->threat_map->{$alevel}->[$aim->x]->[$aim->y];
    my %resamounts = ('Time' => $turns);
    my $cost = 0;
    my $elbereth = $self->writes_elbereth;
    my $elbereth_saves = 0;
    my @extra_msp = ();
    for my $p (keys %$thme) {
	defined($thme->{$p}) or next;
	my ($thmeturns, $planname) = split / /, $p;
	next if $thmeturns >= $turns;
        # The chance that an iterative Elbereth-writing in the dust fails
        # (this is more than 28% due to the chance that it fails more than
        # once.) Note that this makes $thmeturns pretty irrelevant,
        # precisely because the Elbereths stop us being attacked after a
        # while. This has an effect only on Mitigate threats.
        my $esave_multiplier = 0;
        if ($planname =~ /^Mitigate(?!Without)/ && $alevel == $tlevel) {
            my $tplan = $ai->plans->{$planname};
            TAEB->log->ai("$planname has gone missing in Strategic",
                level => 'error'), next unless $tplan;
            my $monster = $tplan->monster;
            if ($monster->glyph ne 'I' && $monster->respects_elbereth) {
                $esave_multiplier = $turns - $thmeturns;
                $thmeturns = $turns - 0.3888 if $elbereth;
            }
        }
        push @extra_msp, $planname;
	my %costs = %{$thme->{$p}};
	for my $resource (keys %costs) {
	    $resamounts{$resource} += $costs{$resource} * ($turns - $thmeturns);
	    $elbereth_saves +=
                $resources->{$resource}->cost(
                    $costs{$resource} * $esave_multiplier);
	}
    }
    for my $resource (keys %resamounts) {
	$cost += $self->cost($resource, $resamounts{$resource});
    }
    $self->elbereth_saves($self->elbereth_saves + $elbereth_saves);
    $self->extra_msp(\@extra_msp);
    return $cost;
}

# Special costs of attacking monsters.  For now, don't even think about
# attacking lawful monsters; eventually this will be more sophisticated,
# and handle things like all the HP we expect to lose attacking them.
sub attack_monster_risk {
    my ($self, $mon) = @_;
    my $spoiler = $mon->spoiler // return; # Is are always safe (for now)
    my $risk = 0;

    # XXX priests, unicorns
    return 0 if ($mon->disposition // '') eq 'hostile';

    # for most monsters, estimate how much it'll hurt if we anger them
    $risk += $self->cost("Impossibility", 1) if $spoiler->name =~
	/shopkeeper|watchman|watch captain|priest/;

    return $risk;
}

# The maximum distance to try to travel. This is divided by 4 upon
# each failed travel (to a minimum of 1), multiplied by 2 upon each
# successful travel (to a maximum of 256).
has travel_distance => (
    isa     => 'Int',
    is      => 'rw',
    default => 256,
);
sub increase_travel_distance {
    my $self = shift;
    my $d = $self->travel_distance;
    $self->travel_distance($d*2) if $d < 256;
}
sub decrease_travel_distance {
    my $self = shift;
    my $d = $self->travel_distance;
    $d = 4 if $d < 4;
    $self->travel_distance($d/4);
}

# Trying this plan. We follow the path if there is one, else perform
# the action if we're where we want to be, else bail.
sub action {
    my $self = shift;
    my $ai   = TAEB->ai;
    $self->used_travel_to(undef);
    return undef unless defined $self->aim_tile_cache;
    # Yes, return the reach action even if there isn't one. It's undef
    # in that case, which is exactly what we want; it's an error to
    # try to path somewhere if we're already there, we should try a
    # different plan instead.
    return $self->reach_action
	if TAEB->current_tile == $self->aim_tile_cache;
    my @chain = $ai->calculate_tme_chain($self->aim_tile_cache);
    return undef unless @chain;
    # We want the first step in the chain, unless we can travel.
    my $firsttactic = $chain[0]->{'tactic'};
    return $firsttactic
        unless $ai->safe_to_travel
            && !$self->mobile_target
            && $firsttactic->replaceable_with_travel;
    my $chainindex = 0;
    $chainindex++ while defined $chain[$chainindex+1]
        && $chain[$chainindex+1]->{'tactic'}->replaceable_with_travel
        && $chainindex < $self->travel_distance;
    my $tme = $chain[$chainindex];
    $chainindex <= 1 and return $firsttactic; # only travel 3+ tiles
    my $tile = $tme->{'tile_level'}->at($tme->{'tile_x'}, $tme->{'tile_y'});
    $self->used_travel_to($tile);
    return TAEB::Action->new_action('travel', target_tile => $tile);
}

# Whether we succeeded. This is called with the tactic as an argument
# if the tactic succeeded, or with undef as argument if it wasn't
# based on a tactic.
sub succeeded {
    my $self = shift;
    if ($self->used_travel_to) {
	$self->increase_travel_distance, return
            ($self->has_reach_action ? undef : 1)
            if $self->aim_tile_cache == TAEB->current_tile;
        return undef if $self->used_travel_to == TAEB->current_tile;
        $self->decrease_travel_distance;
        return undef; # try travelling again, but not as far this time
    }
    if (defined(shift)) {
        return ($self->has_reach_action ? undef : 1)
            if $self->aim_tile_cache == TAEB->current_tile;
        $self->increase_travel_distance;
	return undef;
    }
    # we reached the tile, allow travelling again
    $self->increase_travel_distance;
    return 1 unless $self->has_reach_action;
    return $self->reach_action_succeeded;
}
# Whether the reach action succeeded.
sub reach_action_succeeded { 1 };

__PACKAGE__->meta->make_immutable;
no Moose;

1;
