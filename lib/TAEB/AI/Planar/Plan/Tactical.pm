#!/usr/bin/env perl
package TAEB::AI::Planar::Plan::Tactical;
use TAEB::OO;
use TAEB::AI::Planar::TacticsMapEntry;
use TAEB::Util qw/delta2vi refaddr/;
use Moose;
extends 'TAEB::AI::Planar::Plan';

# Tactical plans. These are similar to strategic plans, but plan
# movement from one tile to the next, rather than the much broader
# scope of strategic plans. Generally speaking, most of the time we
# have a strategic plan (where to go and what to do), and a tactical
# plan (how to get there); the action from the tactical plan is used
# if there is one (unless it's the no-op plan Nop). Instead of being
# based on desirability, tactical plans create tactics map entries;
# most of them will need a tactics map entry to do calculations (apart
# from Nop), which is the tactics needed to reach the square they're
# on. This differs from an argument (which some plans have as well);
# for instance, Walk needs the tile it's pathing to as well as the
# TME. The arguments are sent in the form [level, x, y] (with possibly
# others); the idea is that the arguments should be the same if the
# plan is the same in essence. (This is why the location of the TME is
# sent, not the TME itself; the TMEs will change every step, but that
# doesn't change the essence of what the plan is.) However; the TME
# location is only used to see if two plans are the same; the TME
# itself isn't stored on the plan for efficiency reasons, but instead
# passed round from procedure to procedure as an argument.

# Nearly all tactical plans want this. The one that doesn't can
# override it to an error. A typical argument list for a tactical plan
# looks like [level, x, y], or often [level, x, y, tileto] for plans
# like Walk which are coming from somewhere and going to somewhere.
# The level, x, and y are stored as a TME, but not passed that way.
sub set_arg {
    my $self = shift;
    my @args = @{(shift)};
    splice @args, 0, 3;
    $self->set_additional_args(@args);
}
# However, many tactical plans don't need this one; the ones that
# do can override it.
sub set_additional_args {
    die "Unexpected additional argument" unless @_ == 1; # 1 for ourself
}

# Get the tile corresponding to the passed-in TME.
sub tme_tile {
    my $self = shift;
    my $tme  = shift;
    return $tme->{'tile_level'}->at($tme->{'tile_x'},$tme->{'tile_y'});
}

# Things that should never be called on a tactical plan.
sub spread_desirability { die "Tactical plans cannot spread desirability"; }
sub gain_resource_conversion_desire { die "Tactical plans cannot gain desire"; }
sub planspawn { die "Tactical plan is trying to spawn strategic plans"; }

# Impossibility for tactical plans is based on the tactical success count.
sub appropriate_success_count {
    return TAEB->ai->tactical_success_count;
}

# Marking tactical plans impossible as a method of abandoning is a Bad
# Idea; there are several issues with it (it encourages suboptimal
# methods of doing whatever was a bad idea in the first place, it
# breaks routing assumptions, you need to invalidate caches everywhere
# when it times out). Instead, tactical plans are marked as 'toxic';
# routing's still done using them, but strategic plans that would
# involve routing through them are rejected. Typically, toxicity lasts
# for 5 tactical successes.
has (toxic_until => (
    isa => 'Int',
    is  => 'rw',
    default => -1,
));
# Override abandon in Plan.
sub abandon {
    my $self = shift;
    $self->toxic_until(TAEB->ai->tactical_success_count + 5);
}

# Some tactical plans can be replaced by travelling instead, to save
# time. This should be set to 1 if a travel to the destination of the
# TME would have much the same effect as doing it via actions.
sub replaceable_with_travel { 0 }

# The main entry point for tactical planning. This causes the plan to
# either call add_possible_move to add a possible move from where it
# is at the moment, or to call check_possibility on other plans if
# this is a metaplan (as opposed to spawning via planspawn).
sub check_possibility {
    my $self = shift;
    return if $self->difficulty > 0;
    # Do the plan-specific possibility checks.
    $self->check_possibility_inner(shift);
}
sub check_possibility_inner {
    die "All tactical plans must override check_possibility_inner";
}
# A helper function for check_possibility; call check_possibility on
# another plan, with the same TME (which must be passed in as an
# argument).
sub generate_plan {
    my $self = shift;
    my $tme = shift;
    my $planname = shift;
    my @args = @_;
    my $ai = TAEB->ai;
    $ai->get_tactical_plan($planname, [$tme->{'tile_level'},
				       $tme->{'tile_x'},
				       $tme->{'tile_y'},
				       @args])->check_possibility($tme);
}

# add_possible_move on the plan fills in a tactical map entry, then
# calls add_possible_move on the AI. Nearly all TMEs get created via
# this function; however, as it requires an existing TME to get
# started, at least one is created a different way. This calls
# calculate_risk to get a spending plan, and uses that for risk
# calculations.
sub add_possible_move {
    my $self = shift;
    my $oldtme = shift;
    my $newx = shift;
    my $newy = shift;
    my $oldlevel = $oldtme->{'tile_level'};
    my $newlevel = shift || $oldlevel;
    my $ai = TAEB->ai;
    # We can save a lot of time by not bothering if there's already a
    # current TME for this square.
    my $currenttme = $ai->tactics_map->{refaddr $newlevel}->[$newx]->[$newy];
    return if defined $currenttme and $currenttme->{'step'} == $ai->aistep;
    my $full_recalc = $ai->full_tactical_recalculation;
    $self->next_plan_calculation;
    $self->spending_plan({});
    $self->calculate_risk($oldtme);
    # Make a deep copy of the spending plan, and add the spending plan
    # so far to it.
    my %risk = %{$self->spending_plan};
    $risk{$_} < 0 and warn "Risk of $_ seems to be negative in ".$self->name
        for keys %risk;
    $risk{$_} += $oldtme->{'risk'}->{$_} for keys %{$oldtme->{'risk'}};

    # Work out the added risk from threats, and the plans which will
    # eliminate or reduce it.
    my %msp = %{$oldtme->{'make_safer_plans'}};
    my $msp = \%msp;
    my $oldx = $oldtme->{'tile_x'};
    my $oldy = $oldtme->{'tile_y'};
    # This check assumes no loops involving interlevel pathing; safe in
    # NetHack, but incorrect in Crawl. (TODO: check if this breaks in the
    # entrance to Rodney's.)
    if ($newlevel == TAEB->current_level) {
	# Note: This conditional only matters the turn after full
	# recalculation.  Interlevel updating always ignores threats.
	# XXX Should it?
	my $timetohere = $risk{"Time"} // 0;
        my $timethisstep = $self->spending_plan->{'Time'} // 0;
        # iter = 1: check the destination tile
        # iter = 0: check the source tile
        # It's assumed that a tactic moves as the last thing it does, and
        # stays on the source tile until it's ready; I can't think of a
        # situation where this fails (burden should be taken care of in the
        # threat map), but if there is one, this needs generalising.
        for my $iter (0 .. ($timethisstep > 1 ? 1 : 0)) {
            my $thme = $ai->threat_map->{refaddr $oldlevel}->
                [$iter ? $oldx : $newx]->
                [$iter ? $oldy : $newy];
            for my $p (keys %$thme) {
                # Not all possible values of $p are threats.
                defined($thme->{$p}) or next;
                # If the threat never gets here in time, ignore it.
                my ($turns, $reductionplan) = split / /, $p;
                # Debug code for threat calculation
#                TAEB->log->ai("$self: Threat has $turns, reduced by $reductionplan, tth is $timetohere (iter $iter)");
                $turns > $timetohere and next;
                my $risk_multiplier = $timetohere - $turns;
                if ($iter) {
                    $risk_multiplier = $timethisstep - 1 if $risk_multiplier > $timethisstep - 1;
                } else {
                    $risk_multiplier -= ($timethisstep - 1) if $timethisstep > 1;
                    $risk_multiplier = 1 if $risk_multiplier < 1;
                }
                # Add risk from the threat.
                my %threatrisk = %{$thme->{$p}};
                $threatrisk{$_} < 0 and 
                    warn "Threat risk of $_ seems to be negative in ".$self->name
                    for keys %threatrisk;
                $risk{$_} += $threatrisk{$_} * $risk_multiplier for keys %threatrisk;
                # Some debug code for threat calculation
#                TAEB->log->ai("$self: threat risk is " . (join '|', %threatrisk) .
#                              " multiplied by $risk_multiplier");
                # Add the threat reduction plan.
                $msp->{$reductionplan} += $ai->resources->{$_}->cost($threatrisk{$_})
                    for keys %threatrisk;
            }
	}
    }

    # Create the new TME.
    my $tme = {
	prevtile_level   => $oldlevel,
	prevtile_x       => $oldx,
	prevtile_y       => $oldy,
	risk             => \%risk,
	tactic           => $self,
	tile_x           => $newx,
	tile_y           => $newy,
	tile_level       => $newlevel,
	step             => $ai->aistep,
        make_safer_plans => $msp,
        source           => $full_recalc ? 'world' : 'level',
    };
    # If doing a full recalculation, also update one-level information
    # in the TME. This ignores threats, as there are no threat maps
    # for levels other than the current one. TODO: Risk of returning
    # to a level (due to swarms of monsters surrounding the stairs).

    # FIXME: Actually, there are threat maps for other levels.  Why
    # are we ignoring them again? (Because they haven't been updated
    # at all recently, and therefore are possibly worse than useless;
    # e.g. if we fled upstairs at low hitpoints, a monster near the
    # stairs may look much more threatening than it actually is.)
    if($full_recalc) {
        if ($oldlevel == $newlevel) {
            $tme->{'prevlevel_level'} = $oldtme->{'prevlevel_level'};
            $tme->{'prevlevel_x'} = $oldtme->{'prevlevel_x'};
            $tme->{'prevlevel_y'} = $oldtme->{'prevlevel_y'};
            my %lrisk = %{$self->spending_plan};
            $lrisk{$_} += $oldtme->{'level_risk'}->{$_}
                for keys %{$oldtme->{'level_risk'}};
            $tme->{'level_risk'} = \%lrisk;
        } else {
            $tme->{'prevlevel_level'} = $tme->{'prevtile_level'};
            $tme->{'prevlevel_x'} = $tme->{'prevtile_x'};
            $tme->{'prevlevel_y'} = $tme->{'prevtile_y'};
            $tme->{'level_risk'} = $self->spending_plan;
        }
    }
    bless $tme, "TAEB::AI::Planar::TacticsMapEntry";
    $ai->add_possible_move($tme);
}

__PACKAGE__->meta->make_immutable;
no Moose;

1;
