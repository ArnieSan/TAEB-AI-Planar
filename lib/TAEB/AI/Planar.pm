#!/usr/bin/env perl
package TAEB::AI::Planar;
use TAEB::OO;
use Heap::Simple::XS;
use Scalar::Util qw/refaddr weaken/;
use Time::HiRes qw/gettimeofday tv_interval/;
extends 'TAEB::AI';

# The shortsightedness modifier, or its opposite (lower means more
# shortsighted); the number of turns over which to measure a threat
# that we need to deal with to make it go away (such as a monster
# which will keep attacking us if we don't run or fight). For
# instance, 20 means treat a monster that would attack us every
# turn as as dangerous as something which might do 20 times the
# damage to us, but only once.
use constant repeated_threat_turns => 5;

# The overall plan, what we're aiming towards.
use constant overall_plan => 'Descend';
# The fallback metaplan: what to do if we get stuck.
use constant fallback_plan => 'FallbackMeta';

# A trick to avoid having to loop over things invalidating them;
# instead, store an aistep value, and they're invalidated if it
# doesn't equal the current value.
has aistep => (
    isa     => 'Int',
    is      => 'rw',
    default => 1,
);
# Likewise, tactical and strategic success counts remove the need to
# loop through plans changing their difficulties.
has tactical_success_count => (
    isa     => 'Int',
    is      => 'rw',
    default => 0,
);
has strategic_success_count => (
    isa     => 'Int',
    is      => 'rw',
    default => 0,
);

# Extra information about what we're doing at the moment.
has currently_modifiers => (
    isa     => 'Str',
    is      => 'rw',
    default => '',
);
# Plans.
has plans => (
    isa     => 'HashRef[TAEB::AI::Planar::Plan]',
    is      => 'rw',
    default => sub { {} },
);
has current_plan => (
    isa     => 'Maybe[TAEB::AI::Planar::Plan]',
    is      => 'rw',
    default => undef,
);
# A plan counts as potentially abandoned if it doesn't strategy-fail
# or tactics-fail or succeed. It is actually marked as abandoned if
# a different plan is selected at the next step and it is potentially
# abandoned. This variable holds the current potentially abandoned
# plan, if there is one.
has abandoned_plan => (
    isa     => 'Maybe[TAEB::AI::Planar::Plan]',
    is      => 'rw',
    default => undef,
);
has abandoned_tactical_plan => (
    isa     => 'Maybe[TAEB::AI::Planar::Plan::Tactical]',
    is      => 'rw',
    default => undef,
);
# This list is separate merely for efficiency reasons.
has tactical_plans => (
    isa     => 'HashRef[TAEB::AI::Planar::Plan::Tactical]',
    is      => 'rw',
    default => sub { {} },
);
has current_tactical_plan => (
    isa     => 'Maybe[TAEB::AI::Planar::Plan::Tactical]',
    is      => 'rw',
    default => undef,
);
# Storing plans by the object they refer to speeds up certain
# operations.
has plan_index_by_object => (
    isa     => 'HashRef[ArrayRef[TAEB::AI::Planar::Plan]]',
    is      => 'rw',
    default => sub { {} },
);
# Plans sometimes need to store per-AI persistent data, mostly for
# performance reasons. Give them somewhere they can store it without
# having to hack the core AI and without having different plans clash
# with each other.
has plan_caches => (
    isa     => 'HashRef', # with unknown contents
    is      => 'rw',
    default => sub { {} },
);

# A heap of desire values. This only exists for one calculation, but
# the plans have to be able to get at it somehow, and they do that by
# calling mutator methods of this class itself. Those methods can't
# get at the internals of next_plan_action, so we leave the heap out
# here so we can get at it easily.  The heap holds tuples (implemented
# as array refs) whose first elements are references to plans
# (i.e. shallow copies of things in the plan array); the keys are the
# second elements, which are the desire values. (We're wrapping
# manually, because we need to grab the desire value as part of the
# calculation, generally.) As gaining desire is a max function, rather
# than addition, gaining desire when already in the heap is a simple
# case of generating a duplicate entry, and those duplicates are
# ignored by next_plan_action. The third element of each tuple is a
# boolean which specifies whether the desire value in the heap in this
# element took risk into account or not.
has _planheap => (
    isa    => 'Heap::Simple::XS',
    is      => 'rw',
    default => sub {
	# The type of heap is specified specifically, because we're
	# using dirty optimisations, and their safety varies from heap
	# implementation to heap implementation. (Dirty XS heaps are
	# fine the way we use this one; a dirty > Array implementation
	# causes the desire value to be cached separately, which is
	# fine with us and means Array doesn't lose performance over
	# Object in this case.)
	return Heap::Simple::XS->new(
	    order => ">",             # highest value first
	    elements => [Array => 1], # manually wrapped keys and values
	    dirty => 1,               # safely dirty
	);
    }
);
# Set the desire of a plan to a given value, unless that would make it
# smaller. This is implemented by adding a new heap element. (The
# value passed into this procedure should not take risk into account,
# because this procedure allows for that itself.)
sub add_capped_desire {
    my $self = shift;
    my $plan = shift;
    my $amount = shift;
    my $risk = $plan->risk;
    if(defined $risk) {
	$self->_planheap->insert([$plan, $amount-$risk, 1]);
    } else {
	$self->_planheap->insert([$plan, $amount, 0]);
    }
}

# The tactics heap is out here for much the same reason that the
# strategy plan heap is; the plans themselves need to be able to
# modify it.
has _tacticsheap => (
    isa     => 'Heap::Simple::XS',
    is      => 'rw',
    default => sub {
	return Heap::Simple::XS->new(
	    order => '<',
	    elements => [Object => 'numerical_risk'],
	    dirty => 1,
	);
    }
);
# Add a possible move to the tactics heap.
sub add_possible_move {
    my $self = shift;
    my $tme = shift;
    $self->_tacticsheap->insert($tme);
    # Debug line; comment this out when not in use.
#    TAEB->log->ai("Adding potential tactic " .
#			   $tme->{'tactic'}->name .
#			   " with risk " . $tme->numerical_risk);
}

# Resources.
use constant resource_types => qw/Hitpoints Nutrition Time Zorkmids/;
has resources => (
    isa     => 'HashRef[TAEB::AI::Planar::Resource]',
    is      => 'rw',
    default => sub {
	my $self = shift;
	my %resources = ();
	for my $type (resource_types) {
	    require "TAEB/AI/Planar/Resource/$type.pm";
	    $resources{$type} = "TAEB::AI::Planar::Resource::$type"->new;
	}
	return \%resources;
    },
);

# The tactics map.
# This contains all the pathfinding details for each level. Levels
# other than the one we're on are cached (because nothing on them can
# change); this can lead to inaccurate results sometimes when our
# resource levels change (maybe we should invalidate the cache every
# now and then?), but is necessary for decent performance. The current
# level is recalculated every step.
has tactics_map => (
    isa     =>
        'HashRef[ArrayRef[ArrayRef[TAEB::AI::Planar::TacticsMapEntry]]]',
    is      => 'rw',
    default => sub { {} },
);

# The threat map.
# This contains information about which squares on the current level
# are dangerous. Again, levels other than the one we're on are cached.
# The current level is recalculated every step.

# Each tile is stored as a hash whose keys are the turns on which the
# threats first affect the tile (relative to the current turn, which
# is 0), and whose values are the amount of resource cost involved (in
# typical resource-amount hash format). The keys are actually of the
# form "$turn $planname"; this gives them a numerical value of the
# turn, but allows different plans to share a turn number.
# The hash can have other keys to indicate monster routing
# information: "fly", "swim", and "walk" are possible monster movement
# types that are included in the hash, with undef used as the value if
# that movement type can walk there, and the key omitted if that
# movement type can't. Phasers can walk anywhere.
has threat_map => (
    isa     => 'HashRef[ArrayRef[ArrayRef[HashRef[Maybe[HashRef[Num]]]]]]',
    is      => 'rw',
    default => sub { {} },
);

# For profiling
has lasttimeofday => (
    isa     => 'Maybe[ArrayRef]',
    is      => 'rw',
    default => undef,
);

sub next_action {
    my $self = shift;
    my $t0 = [gettimeofday];
    my $t1;
    TAEB->log->ai("Time taken outside next_action: ".
			   tv_interval($self->lasttimeofday,$t0)."s.",
			   level => 'debug')
	if defined $self->lasttimeofday;
    # Go to the next AI step, invalidating everything from last step
    # in the process.
    $self->aistep($self->aistep + 1);
    # Did we abandon a plan last turn?
    if (defined $self->abandoned_plan && defined $self->current_plan &&
	$self->abandoned_plan->name ne $self->current_plan->name) {
	# Prevent oscillations; if a plan is abandoned, we don't try it
	# again for a while. (mark_impossible will try a plan twice before
	# suspending it for a while; and remember that dependencies and
	# excursions will mark other plans possible when they succeed.)
	$self->abandoned_plan->mark_impossible;
	TAEB->log->ai("Plan ".$self->abandoned_plan->name.
			       " was abandoned.");
	# More interestingly, we also abandon the tactical plan we
	# were trying, if there is one; even though it quite possibly
	# succeeded! This is to prevent oscillations; if we try the
	# same tactical plan any time soon, we're definitely
	# oscillating and need to try going in the other direction.
	if (defined $self->abandoned_tactical_plan) {
	    $self->abandoned_tactical_plan->mark_impossible;
	    TAEB->log->ai("Tactical plan ".
				   $self->abandoned_tactical_plan->name.
				   " was abandoned.");
	}
    }
    # Did the plan succeed, or fail, or is it ongoing?
    my $succeeded = undef;
    if (defined $self->current_tactical_plan) {
	# Work out success based on the current tactical plan
	$succeeded = $self->current_tactical_plan->succeeded;
	defined $succeeded and $succeeded and
	    $self->tactical_success_count($self->tactical_success_count+1),
	    TAEB->log->ai("OK, tactic ".
				   $self->current_tactical_plan->name.
				   " worked.", level => 'debug');
	defined $succeeded and !$succeeded and
	    $self->current_tactical_plan->mark_impossible,
	    TAEB->log->ai("Ugh, tactic ".
				   $self->current_tactical_plan->name.
				   " failed...", level => 'info');
    }
    if ((defined $succeeded && $succeeded == 1) ||
	!defined $self->current_tactical_plan)
    {
	# Work out success based on the current strategic plan.
	defined($self->current_plan) and
	    $succeeded = $self->current_plan->succeeded(
		$self->current_tactical_plan);
	# If the plan succeeded, maybe other plans will have an easier job
	# as a result.
	defined $succeeded and $succeeded and
	    TAEB->log->ai("Yay, plan ".$self->current_plan->name.
				   " succeeded!", level => 'info'),
	    $self->current_plan->reactivate_dependencies,
	    $self->strategic_success_count($self->strategic_success_count+1);

	# If the plan failed, mark it as impossible, so it takes a while
	# before we do cost calculations based on it or try to enact it
	# again. (This prevents oscillations, we aren't going to keep
	# trying two things alternately if they keep failing.) More
	# commonly, plans will become marked possible due to dependencies
	# rather than due to timeout, though; timeout just allows for
	# going back to failed plans every now and then in the hope that
	# something's happened that makes them possible (such as the
	# monster that was causing oscillations having moved).
	defined $succeeded and !$succeeded and
	    TAEB->log->ai("Aargh, plan ".$self->current_plan->name.
				   " failed!", level => 'info'),
	    $self->current_plan->mark_impossible;
    }
    if (!defined $succeeded) {
	# This plan is potentially an abandoned one. (It will /actually/ be
	# abandoned if it's potentially abandoned and isn't used on the next
	# step.)
	$self->abandoned_plan($self->current_plan);
	$self->abandoned_tactical_plan($self->current_tactical_plan);
    } else {
	$self->abandoned_plan(undef);
    }

    # Invalidate plans now so that any of the next few steps can
    # re-validate them.
    $_->invalidate for values %{$self->plans};

    $t1 = [gettimeofday];
    TAEB->log->ai("Time taken for success measurement: ".
			   tv_interval($t0,$t1)."s.", level => 'debug');

    # Place threats on the threat map.
    $self->threat_check;
    $t0 = [gettimeofday];
    TAEB->log->ai("Time taken for threat check: ".
			   tv_interval($t1,$t0)."s.", level => 'debug');

    # Create the tactical map.
    $self->update_tactical_map;
    $t1 = [gettimeofday];
    TAEB->log->ai("Time taken for tactical map: ".
			   tv_interval($t0,$t1)."s.", level => 'debug');

    # Find our plan for this step.
    my ($plan, $action) = $self->next_plan_action;
    $self->current_plan($plan);
    $t0 = [gettimeofday];
    TAEB->log->ai("Time taken for strategic planning: ".
			   tv_interval($t1,$t0)."s.", level => 'debug');
    $self->lasttimeofday($t0);
    # We need to tell if the return value was an action or a tactical
    # plan. We do this by seeing if the class ISA tactical plan; if it
    # is, then it almost certainly isn't an action (and even if it
    # were, we have to do something in that situation, not that it
    # should ever be allowed to happen in the first place).
    if($action->isa('TAEB::AI::Planar::Plan::Tactical')) {
	# It's a tactical plan.
	$self->currently($self->currently_modifiers .
			 $plan->description . ' > ' .
			 $action->description);
	$self->current_tactical_plan($action);
	my $inner_action = $action->try;
	return $inner_action if defined $inner_action;
	# OK, we have an impossible tactic on our hands. The solution
	# here is to repeat the entire plan-finding process without
	# that tactic included. (This shouldn't happen very often, if
	# it does that plan's plan-calculation needs looking at.)
	$self->current_tactical_plan(undef);
	$self->current_plan(undef);
	TAEB->log->ai("Tactical plan ".($action->name).
			       " failed to produce an action, marking it".
			       " as impossible...", level => 'debug');
	@_ = ($self);
	goto &next_action; # tail-recursion
    } else {
	$self->currently($self->currently_modifiers . $plan->description);
	$self->current_tactical_plan(undef);
	return $action;
    }
}

# The actual AIing.
sub next_plan_action {
    my $self = shift;
    my $action = undef;
    my $plan;
    # This AI works by selecting a plan of action, then enacting it.
    # Plans range from the very general or very optimistic ("Deal with
    # that jackal") or ("Offer the Amulet of Yendor on the appropriate
    # high altar") down to the low- level and mundane ("Exchange 5
    # turns and 1 food ration for 800 nutrition and 20 carrying
    # capacity, by eating a food ration").

    # Before choosing a plan, let's search for new plans that might
    # have become available, and old plans that now might be
    # nonexistent rather than just impossible (e.g. item plans for
    # items that have been used up), and update the plan list to allow
    # for these. Even for monster-elimination plans (which are handled
    # by threat_check), we still need to know which plans are current,
    # and we can't delete/recreate them because that would reset
    # difficulty levels. Plans auto-invalidate if they refer to a
    # monster or item (and do not auto-invalidate otherwise, but can
    # self-invalidate if necessary); this loop revalidates all plans
    # which refer to monsters or items which still exist.

    # Invalidate and destroy plans referring to nonexistent things.
    # (The plans themselves will refuse to be invalidated if they
    # always refer to something that exists, like a tile.)
    # The invalidation is done before threat check, so it can validate
    # plans too.
    my @refs = (TAEB->current_level->has_enemies,
		TAEB->inventory->items,
		TAEB->current_level->items);
    for my $ref (@refs) {
	my $addr = refaddr($ref);
	/\[$addr\]/ and $self->plans->{$_}->validate for keys %{$self->plans};
    }
    # Create plans for items and map features, if necessary.
    for my $item (TAEB->inventory->items) {
	$self->get_plan("InventoryItemMeta",$item);
    }
    for my $item (TAEB->current_level->items) {
	$self->get_plan("GroundItemMeta",$item);
    }
    TAEB->current_level->each_tile(sub {
	my $tile = shift;
	# Interesting tiles have Investigate as a metaplan. These are
	# tiles on which we know there are items, but not what.
	$tile->is_interesting and $self->get_plan("Investigate",$tile);
    });
    $_->planspawn for values %{$self->plans};
    # Delete any plans which are still invalid.
    for my $planname (keys %{$self->plans}) {
	delete $self->plans->{$planname}
	    unless $self->plans->{$planname}->validity;
    }

    # The plan is selected using "desire values". A plan starts with 0
    # desire at the start of the game, and gains desire from the
    # following sources (with desire fading over time if it is not
    # constantly topped up):
    $_->next_plan_calculation for values %{$self->plans};
    $self->_planheap->clear;

    # Resource conversion. If we're running low on a resource, then we
    # produce desire to gain that resource. The amount of desire, for
    # each plan that could produce that resource by converting
    # different resources, is equal to the amount of value gained.
    # Note that resources are much more valuable when low, when we
    # can't top them up easily, or when they are in demand; the value
    # of a resource goes down over time, and goes up whenever a plan
    # that we want to carry out requires that resource (whether the
    # plan succeeds or fails due to lack of resources).
    $_->gain_resource_conversion_desire for values %{$self->plans};

    # An overall plan. There is always one plan that gets a continuous
    # baseline trickle of desire, to determine what to do if we have
    # nothing better to do. This is generally a high-level idealistic
    # one, such as winning the game, which nearly always fails but
    # passes its desire onto more practical plans that will make it
    # eventually possible. This gets no desire now; it gains desire
    # steadily until some plan seems like a good idea, when the AI
    # can't think of anything better to do.

    # The main loop. Look for the most desirable plan we have at the
    # moment, and calculate its possibility. If it's possible,
    # calculate its risk, or try it if it was already possible. If
    # it's impossible, let it spread desire. If we haven't tried a
    # plan, go onto the new most desirable possible plan.
    my $iterations = 0;
    # planstate is the highest desire at which we've tried this plan
    # so far (using plans as the hash keys), or undef if it's untried.
    my %planstate = ();
    my $bestplanname;
    my $majorplan = overall_plan;
    $self->currently_modifiers('');
    while (1) {
	my $desire;
	$plan = undef;
	{
	    my $heapentry = $self->_planheap->extract_first;
	    my $withrisk;
	    # If there was no result, bail out to the block that tries
	    # to manipulate things to give us a result.
	    (($plan=undef), last) unless defined $heapentry;
	    ($plan,$desire,$withrisk) = @$heapentry;
	    # Likewise, bail if all plans are undesirable.
	    (($plan=undef), last) if $desire <= 0;
	    # If this heap entry was calculated without taking risk
	    # into account, but we now have more accurate figures,
	    # ignore in favour of those (lower) figures.
	    redo if defined($plan->risk) && !$withrisk;
	    # If this plan was already calculated at or above the
	    # given desirability, no point in trying again, that'll
	    # just do a lot of NOPing for no reason, and possibly
	    # lead to an infinite loop. The 1e-8 is because floating
	    # point comparisons are always a bit fuzzy.
	    redo if exists($planstate{$plan})
		 && $planstate{$plan} >= $desire-(1e-8);
	}
	if (!defined $plan) {
	    if (++$iterations > 3) {
		die 'No plans seem possible at all!' if $iterations > 8;
		# Decay impossibility a bit, and try the whole thing
		# again, in a desperate attempt to find some plan we
		# can use. If all plans are locked out like this, it
		# means that we have either a severe dependency mess-
		# up or something's happened to us that we don't know
		# how to handle.
		TAEB->log->ai(
		    'Decaying impossibility to try to find a plan...',
		    level => 'info');
		$self->currently_modifiers('[Retry] ');
		$self->strategic_success_count(
		    $self->strategic_success_count+3);
		$self->tactical_success_count(
		    $self->tactical_success_count+3);
		if ($iterations > 6) {
		    # We're utterly stumped. Wipe out the
		    # impossibility records, so that we'll retry
		    # anything, even if it seems sure to fail. Maybe
		    # we'll get somewhere by repeating plans until
		    # something else happens.
		    TAEB->log->ai(
			'Blanking impossibility to try to find a plan...',
			level => 'info');
		    $self->currently_modifiers('[Major retry] ');
		    $self->strategic_success_count(
			$self->strategic_success_count+10000);
		    $self->tactical_success_count(
			$self->tactical_success_count+10000);
		}
		if ($iterations > 7) {
		    # There are no positive-desirability plans. Let's
		    # see how the fallbacks work out.
		    $majorplan = fallback_plan;
		    $self->currently_modifiers('[Fallback] ');
		}
		$self->_planheap->clear;
		%planstate = ();
	    }
	    $self->add_capped_desire($self->get_plan($majorplan),
				     10000000);
	    next;
	}
	$bestplanname = $plan->name;
	# The plan needs to know how raw-desirable it is, and how
	# desirable if risk is accounted for, so it can spread
	# desirability (from calculate_risk or spread_desirability).
	$plan->desire($desire+($plan->risk||0));
	$plan->desire_with_risk($desire);
	# If the plan has zero difficulty and uncalculated risk,
	# calculate its risk (possibly spreading desire onto things
	# that would make it less risky).
	if ($plan->difficulty <= 0 &&
	    $plan->risk_valid_on_step != $self->aistep) {
	    $plan->risk_valid_on_step($self->aistep);
	    $plan->spending_plan({});
	    $plan->risk($plan->calculate_risk);
	    # Some more debugging lines that I seem to use a lot
#	    TAEB->log->ai(
#		"Risk of $bestplanname calculated at ".$plan->risk);
#	    TAEB->log->ai("Desire was $desire");
	    # Reinsert the plan with the same desire level; it'll be
	    # updated for the new risk value
	    $self->add_capped_desire($plan, $desire);
	    next;
	}
	$planstate{$plan} = $desire; # we're retrying
	# If the plan has zero difficulty and calculated risk, try it!
	if ($plan->difficulty <= 0) {
	    # try returns either an action, a tactical plan, or undef.
	    # If it's undef, the plan failed, otherwise we're going to
	    # try to carry it out directly with NetHack (rather than
	    # just in our mind).
	    $action = $plan->try;
	    last if $action;
	}
	# Seems it was impossible. Oh well...
	$plan->spread_desirability;
    }
    TAEB->log->ai("Plan $bestplanname thinks it's possible, ".
			   "enacting it.", level => 'info');
    return ($plan, $action);
}

sub update_tactical_map {
    my $self = shift;
    my $map = $self->tactics_map;
    my $curlevel = TAEB->current_level;
    my $curlevelra = refaddr($curlevel);
    # Blank the map for the current level, if we need to. (If the map
    # already exists, then we just let it auto-invalidate due to the
    # step number being out of date. However, the map has to be
    # created in the first place somehow.)
    if (!exists $map->{$curlevel}) {
	$map->{$curlevel} = [];
	my $levelmap = $map->{$curlevel};
	# MAGIC NUMBER alert! Should this be centralised somewhere?
	$levelmap->[$_] = [] for 0..79;
    }
    # Dijkstra's algorithm is used to flood the level with pathfinding
    # data. The heap contains TacticsMapEntry elements.
    my $heap = $self->_tacticsheap;
    $heap->clear;
    # Initialise. We can path to the square we're on without issue and
    # without risk (as it's a NOP).
    $self->get_tactical_plan("Nop")->check_possibility;
    while ($heap->count) {
	my $tme = $heap->extract_top;
	# If we're off the level, just ignore this TME, to avoid
	# updating the entire dungeon every step, unless it specifies
	# prevtile_level incorrectly (and therefore hasn't been
	# updated since we entered the level we're on).
	# The whole dungeon /is/ updated when we change level.
	next if refaddr($tme->{'tile_level'}) != $curlevelra
	     && defined $map->{$tme->{'tile_level'}}
	     && defined	$map->{$tme->{'tile_level'}}->[$tme->{'tile_x'}]
		            ->[$tme->{'tile_y'}]
	     && defined	$map->{$tme->{'tile_level'}}->[$tme->{'tile_x'}]
	                    ->[$tme->{'tile_y'}]->{'prevtile_level'}
	     && refaddr($map->{$tme->{'tile_level'}}->[$tme->{'tile_x'}]
		      ->[$tme->{'tile_y'}]->{'prevtile_level'}) == $curlevelra;
	# If we've already found an easier way to get here, ignore
	# this method of getting here.
	next if exists $map->{$tme->{'tile_level'}}->[$tme->{'tile_x'}]
	                   ->[$tme->{'tile_y'}]
	     && $map->{$tme->{'tile_level'}}->[$tme->{'tile_x'}]
	            ->[$tme->{'tile_y'}]->{'step'} == $self->aistep;
	# This is the best way to get here; add it to the tactical
	# map, then spread possibility from it via the MoveFrom
	# metaplan.
	$map->{$tme->{'tile_level'}}->[$tme->{'tile_x'}]->[$tme->{'tile_y'}]
	    = $tme;
	# The next line is debug code only, but I seem to use it far too
	# often. Just comment it out, don't remove it.
#	TAEB->log->ai("Locking in TME at ".$tme->{'tile_x'}.
#				", ".$tme->{'tile_y'});
	$self->get_tactical_plan("MoveFrom", [$tme->{'tile_level'},
					      $tme->{'tile_x'},
					      $tme->{'tile_y'}])->
						  check_possibility($tme);
    }
}

# Add a threat to the threat map.
sub add_threat {
    my $self = shift;
    my $planname = shift;
    my $danger = shift; # a hashref resource=>amount
    my $tile = shift;
    my $relspeed = shift;
    my $movetype = shift;
    my $threatmap = $self->threat_map->{TAEB->current_level};
    # We flood the threat map with information about this threat.
    # This is done using a heap with elements of the form
    # [monsterturns, x, y], and a simple map which records if each
    # cell has been visited on this run of the procedure.
    my $heap = Heap::Simple::XS->new(
	order => '<',             # lowest first
	elements => [Array => 0], # manually wrapped
	dirty => 1,               # safe in this context
    );
    my @visitmap = ();
    $visitmap[$_] = [] for 0..79;
    # Don't divide by zero if we meet an immobile monster.
    $relspeed or $relspeed = 0.1;
    # We exploit the fact that all monsters can attack all squares
    # that they could move to on the turn after; so it can attack the
    # square it's on on "turn -1", and the squares adjacent to it on
    # turn 0.
    $heap->insert([-1, $tile->x, $tile->y]);
    while($heap->count) {
	my ($t, $x, $y) = @{$heap->extract_first};
	next if $x < 0;
	next if $x > 79;
	next if $y < 1;
	next if $y > 21;
	next if $visitmap[$x]->[$y];
	$visitmap[$x]->[$y] = 1;
	my $rt = $t / $relspeed;
	$threatmap->[$x]->[$y]->{"$rt $planname"} = $danger;
	if ($movetype eq 'phase' || exists $threatmap->[$x]->[$y]->{$movetype})
	{
	    # The monster can attack here on turn t, so it can move here on
	    # turn t and so be in range to attack adjacent cells on turn t+1.
	    $t++;
	    $heap->insert([$t, $x+1, $y  ]);
	    $heap->insert([$t, $x+1, $y+1]);
	    $heap->insert([$t, $x  , $y+1]);
	    $heap->insert([$t, $x-1, $y+1]);
	    $heap->insert([$t, $x-1, $y  ]);
	    $heap->insert([$t, $x-1, $y-1]);
	    $heap->insert([$t, $x  , $y-1]);
	    $heap->insert([$t, $x+1, $y-1]);
	}
    }
}

# What the tactical map does for us; we can form a TME chain in order
# to get a path somewhere. Or we can just get the final TME, if we
# need to know the cost but not the route.
sub calculate_tme_chain {
    my $self  = shift;
    my $tile  = shift;
    my $tme   = $self->tme_from_tile($tile);
    my $map   = $self->tactics_map;
    my @chain = ();
    while(defined $tme && defined $tme->{'prevtile_level'}) {
	unshift @chain, $tme;
	$tme=$map->{$tme->{'prevtile_level'}}->[$tme->{'prevtile_x'}]
	         ->[$tme->{'prevtile_y'}];
    }
    return @chain;
}
sub tme_from_tile {
    my $self = shift;
    my $tile = shift;
    my $map  = $self->tactics_map->{$tile->level};
    return undef unless defined $map; # it might be on an unpathed level
    my $tme  = $map->[$tile->x]->[$tile->y];
    return undef unless defined $tme; # we might not be able to route there
    return $tme if $tme->{'step'} == $self->aistep;
    # If the TME's out of date but on our level, it means we had a routing
    # failure.
    return undef if $tile->level == TAEB->current_level;
    # TODO: Get an updated interlevel TME, if needed.
    return $tme;
}

sub monster_is_peaceful {
    my $self = shift;
    my $monster = shift;
    my $rv = $monster->disposition eq 'peaceful'
          || $monster->disposition eq 'tame';
    return $rv;
}

sub threat_check {
    my $self = shift;
    # Clear the threat map for the current level.
    my $current_level = TAEB->current_level;
    my $threat_map = $self->threat_map;
    my $tmcl = $threat_map->{$current_level} = [];
    # Mark squares on the threat map as impassable to monsters, if
    # necessary. Monster routing is much more primitive than player
    # routing, for efficiency reasons.
    for my $x (0..79) {
	my $col = $tmcl->[$x] = [];
	for my $y (1..21) {
	    my $type = $current_level->at($x,$y)->type;
	    my $coly = $col->[$y] = {};
 	    if ($type eq 'rock' || $type eq 'closeddoor' ||
		$type eq 'wall' || $type eq 'drawbridge' ||
		$type eq 'unexplored') {
		$coly->{'phase'} = undef;
	    }
 	    elsif ($type eq 'pool')       {$coly->{'fly'}  = undef;
 					   $coly->{'swim'} = undef;}
 	    elsif ($type eq 'lava')       {$coly->{'fly'}  = undef;}
 	    elsif ($type eq 'underwater') {$coly->{'swim'} = undef;}
 	    else {
 		$coly->{'fly'} = undef;
 		$coly->{'swim'} = undef;
 		$coly->{'walk'} = undef;
 	    }
	}
    }
    # The most important threats in the game are monsters on the
    # current level.
    my @enemies = $current_level->has_enemies;
    my $selfspeed = TAEB->speed; # invariant code motion
    for my $enemy (@enemies) {
	# Work out what type of enemy this is. If we know its spoiler
	# from its Monster.pm data (i.e. unique glyph and colour),
	# then use that; otherwise, farlook at it and see if we have a
	# spoiler from that.
	$enemy->farlook;
	my $spoiler = $enemy->spoiler;
	my $danger = {};
	my $tile = $enemy->tile;
	my $relspeed = 0.99; # to encourage running away from unknown monsters
        # Tame and peaceful monsters are not threats.
        next if $enemy->disposition eq 'peaceful';
        next if $enemy->disposition eq 'tame';
	if (defined($spoiler)) {
	    # Passive-attack-only monsters are not dangerous to walk past,
	    # and therefore not threats (they're risky to attack, but not
	    # threatty).
	    my $passive_only = 1;
            $passive_only &&= ($_->{mode} eq 'passive') for @{$spoiler->attacks};
	    next if $passive_only;
	    # Use the built-in TAEB average-damage function.
	    my $damagepotential = $enemy->average_melee_damage;
	    $danger = {'Hitpoints' => $damagepotential};
	    $relspeed = $$spoiler{speed} / $selfspeed;
	} else { # use a stock value as we don't know...
	    $danger = {'Hitpoints' => 5};
	}
	my $plan = $self->get_plan("Eliminate",$enemy);
	# Until we have information about what can fly in the spoilers...
	$self->add_threat($plan->name,$danger,$tile,$relspeed,'walk');
	$plan->validate();
    }
    # As an entirely different type of threat (where 'threat' is
    # defined as 'something that makes it more expensive to move
    # here'), we have traps we're currently stuck in. Bear-traps,
    # pits, and webs need to be escaped first, so we mark them as
    # high-risk threats (with the correct risk value being used to
    # represent the cost of the make-safer plan that removes the
    # threat in question).
    my $trapturns = 0;
    TAEB->in_beartrap and $trapturns = 7;
    TAEB->in_pit and $trapturns = 10;
    TAEB->in_web and $trapturns = 1;
    if ($trapturns) {
	my $threatmap = $self->threat_map->{TAEB->current_level};
	TAEB->current_tile->each_adjacent(sub {
	    my $tile = shift;
	    # The *1000 here is to make barging out of the trap more
	    # expensive than getting out the 'proper' way.
	    $threatmap->[$tile->x]->[$tile->y]->{"-1 Extricate"}
	        = {Time => $trapturns * 1000};
	});
	$self->get_plan("Extricate")->validate();
    }
}

# Naming a plan.
sub planname {
    my $self = shift;
    my $name = shift;
    my $arg  = shift;
    if(ref $arg eq 'ARRAY') {
	# Multiple arguments are often sent like this, but
	# unfortunately we can't just use the refaddr of the array ref
	# as it's likely to have been recreated anew. Instead, we run
	# through the elements, printing refaddrs of references and
	# stringifications of nonreferences. That way, passing the
	# same argument list twice leads to a plan with the same name,
	# and it's the names that are compared to see if two plans are
	# the same.
	$name .= '[';
	$name .= join ',', map {ref $_ ? refaddr $_ : $_} @{$arg};
	return $name."]";
    }
    defined($arg) and return "$name\[".refaddr($arg)."]";
    return $name;
}

# Find a plan in the plan list, creating it if it isn't there at the
# moment.
sub get_plan {
    my $self = shift;
    my $name = shift;
    my $arg  = shift;
    my $planname = $self->planname($name,$arg);
    exists $self->plans->{$planname}
        or $self->create_plan('strategic',$name,$arg,$planname);
    return $self->plans->{$planname};
}
sub get_tactical_plan {
    my $self = shift;
    my $name = shift;
    my $arg  = shift;
    my $planname = $self->planname($name,$arg);
    exists $self->tactical_plans->{$planname}
        or $self->create_plan('tactical',$name,$arg,$planname);
    return $self->tactical_plans->{$planname};
}

# Create a new plan.
sub create_plan {
    my $self = shift;
    my $type = shift;
    my $name = shift;
    my $arg  = shift;
    my $planname = shift;
    my $pkg = "TAEB::AI::Planar::Plan::$name";
    my $plan = $pkg->new;
    defined $arg and $plan->set_arg($arg);
    $plan->name($planname);
    if ($type eq 'strategic') {
	$self->plans->{$planname} = $plan;
    } else {
	$self->tactical_plans->{$planname} = $plan;
    }
    if($planname =~ /([0-9]+)\]/) {
	my $pibo = $self->plan_index_by_object;
	defined $pibo->{$1}
	    ? $pibo->{$1} = [$plan]
	    : unshift @{$pibo->{$1}}, $plan;
	# Garbage collector magic.
	weaken $pibo->{$1}->[0];
    }
}

around institute => sub {
    my $orig = shift;
    my $self = shift;

    $orig->($self);

    # Load plans.
    TAEB->log->ai("Loading plans...");

    # Require the module for each plan we could use.
    # The list here is of plans referenced by the core AI itself.
    my @planlist = (
	# Validity metaplans
	"InventoryItemMeta", # metaplan for inventory items
	"GroundItemMeta",    # metaplan for floor items
	"Investigate",       # metaplan for interesting tiles
	# Threat metaplans
	"Eliminate",         # metaplan for monsters
	"Extricate",         # metaplan for traps we're in
	# Tactical metaplans
	"MoveFrom",          # tactical metaplan for tiles
	"Nop",               # stub tactical plan
	# Goal metaplans
	fallback_plan,       # metaplan for fallback
	overall_plan);       # metaplan for strategy
    my %processed = ();

    # Load each plan, and recursively load its references.
    while (@planlist) {
	my $planname = shift @planlist;
	next if $processed{$planname};
	$processed{$planname} = 1;
	my $pkg = "TAEB::AI::Planar::Plan::$planname";
	TAEB->log->ai("Loading plan $planname");
	require "TAEB/AI/Planar/Plan/$planname.pm";
	my @referencedplans = @{$pkg->new->references};
	@planlist = (@planlist, @referencedplans);
    }
};

#####################################################################
# Things below this line should be elsewhere or handled differently

has try_again_step => (
    isa => 'Int',
    is  => 'rw',
    default => -1,
);

# Responding to messages.
sub msg_door {
    my $self = shift;
    my $what = shift;
    if($what eq 'resists') {
	# The door actions can safely try again.
	$self->try_again_step(TAEB->step);
    }
}
sub msg_tile_update {
    # This might have made plans with the tile in question as an
    # argument possible, when they weren't before. We look through
    # the plan index by object to find them.
    my $self = shift;
    my $tile = shift;
    my $addr = refaddr($tile);
    defined $_ and $_->required_success_count(0)
	for @{$self->plan_index_by_object->{$addr}};
}

# Item value.
sub item_value {
    my $self = shift;
    my $item = shift;
    my $resources = $self->resources;
    # If the item is permafood, its value is its nutrition minus its
    # weight; its nutrition is measured in unscarce units (twice the
    # base value for permafood), but its weight is measured in dynamic
    # units. (That allows us to drop things when we get burdened.)
    if($item->isa('TAEB::World::Item::Food')
    &&!$item->isa('TAEB::World::Item::Food::Corpse')
    && $item->is_safely_edible) {
	return 0 unless $item->nutrition;
	return $resources->{'Nutrition'}->base_value * 2 *
	    $item->nutrition;
    }
    return 0;
}
sub pickup {
    my $self = shift;
    my $item = shift;
    return $self->item_value($item) > 0;
}
sub drop {
    my $self = shift;
    my $item = shift;
    return $self->item_value($item) < 0;
}

__PACKAGE__->meta->make_immutable;
no Moose;

1;
