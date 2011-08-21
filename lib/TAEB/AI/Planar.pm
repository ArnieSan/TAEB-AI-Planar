#!/usr/bin/env perl
package TAEB::AI::Planar;
use TAEB::OO;
use Moose;
use Heap::Simple::XS;
use TAEB::Util qw/refaddr weaken display_ro :colors any max deltas/;
use Scalar::Util qw/reftype/;
use Time::HiRes qw/gettimeofday tv_interval/;
use TAEB::Spoilers::Combat;
use TAEB::Spoilers::Sokoban;
use TAEB::AI::Planar::TacticsMapEntry qw/numerical_risk_from_spending_plan/;
use TAEB::AI::Planar::Plan::Tunnel;
use Storable qw/dclone/;
use Set::Object qw/weak_set/;
use Tie::RefHash;
use POSIX qw/floor/;
use Module::Pluggable
    'search_path' => ['TAEB::AI::Planar::Resource'],
    'sub_name' => 'resource_names',
    'require' => 1;
#use Data::Dumper; # needed for debug code, not for general use
extends 'TAEB::AI';

# The shortsightedness modifier, or its opposite (lower means more
# shortsighted); the number of turns over which to measure a threat
# that we need to deal with to make it go away (such as a monster
# which will keep attacking us if we don't run or fight). For
# instance, 20 means treat a monster that would attack us every
# turn as as dangerous as something which might do 20 times the
# damage to us, but only once.

# Conversely, this multiplies the value of permanent resources; when
# this is high, we really like getting items, cursechecking, etc.  Note
# that in many cases the risk of getting items is multiplied by this, so
# the desire had better be too.

# In general, this has the effect of making TAEB more of a "neat freak",
# while lower values give it more options.  So we make it depend on the
# difficulty of finding actions; it increases when ideas are easy, and
# decreases when they aren't.
has (analysis_window => (
    isa     => 'Num',
    is      => 'rw',
    default => 1,
));

# The overall plan, what we're aiming towards.
has (overall_plan => (
    isa     => 'Str',
    is      => 'rw',
    default => sub {
	TAEB->config->get_ai_config->{'overall_plan'} // 'SlowDescent';
    },
    trigger => sub { shift->loadplans },
    traits  => [qw/TAEB::AI::Planar::Meta::Trait::DontFreeze/],
));
# Turn on expensive sanity checks?
has (sanity_checks => (
    isa     => 'Bool',
    is      => 'rw',
    default => sub {
	TAEB->config->get_ai_config->{'sanity_checks'} // 1;
    },
    traits  => [qw/TAEB::AI::Planar::Meta::Trait::DontFreeze/],
));
# Never use travel?
has (veto_travel => (
    isa     => 'Bool',
    is      => 'rw',
    default => sub {
	TAEB->config->get_ai_config->{'veto_travel'} // 0;
    },
    traits  => [qw/TAEB::AI::Planar::Meta::Trait::DontFreeze/],
));
# Which tactical algorithm to use.
# Currently existing algorithms:
# 'level' : Update the current level every step;
# 'world' : Update the entire dungeon every step;
# 'chokepoint' : Update only between chokepoints when possible
has (tactical_algorithm => (
    isa     => 'Str', # TODO: A proper type constraint
    is      => 'rw',
    default => sub {
	TAEB->config->get_ai_config->{'tactical_algorithm'}
            // 'chokepoint';
    },
    traits  => [qw/TAEB::AI::Planar::Meta::Trait::DontFreeze/],
));


# A trick to avoid having to loop over things invalidating them;
# instead, store an aistep value, and they're invalidated if it
# doesn't equal the current value.
has (aistep => (
    isa     => 'Int',
    is      => 'rw',
    default => 1,
));
# Likewise, tactical and strategic success counts remove the need to
# loop through plans changing their difficulties.
has (tactical_success_count => (
    isa     => 'Int',
    is      => 'rw',
    default => 0,
));
has (strategic_success_count => (
    isa     => 'Int',
    is      => 'rw',
    default => 0,
));

# What we're doing at the moment.
has ('+currently' => (
    traits  => [qw/TAEB::AI::Planar::Meta::Trait::DontFreeze/],
));
has (currently_modifiers => (
    isa     => 'Str',
    is      => 'rw',
    default => '',
    traits  => [qw/TAEB::AI::Planar::Meta::Trait::DontFreeze/],
));
# Plans.
has (plans => (
    isa     => 'HashRef[TAEB::AI::Planar::Plan]',
    is      => 'rw',
    default => sub { {} },
    traits  => [qw/TAEB::AI::Planar::Meta::Trait::DontFreeze/],
));
has (current_plan => (
    isa     => 'Maybe[TAEB::AI::Planar::Plan]',
    is      => 'rw',
    default => undef,
    traits  => [qw/TAEB::AI::Planar::Meta::Trait::DontFreeze/],
));
# Keeping track of adding and removing plans.
has (validitychanged => (
    isa     => 'Bool',
    default => 1,
    is      => 'rw',
    traits  => [qw/TAEB::AI::Planar::Meta::Trait::DontFreeze/],
));
# Past plans, to detect flapping oscillations.
has (old_plans => (
    isa     => 'ArrayRef[TAEB::AI::Planar::Plan]',
    is      => 'rw',
    default => sub { [] },
    traits  => [qw/TAEB::AI::Planar::Meta::Trait::DontFreeze/],
));
has (old_tactical_plans => (
    isa     => 'ArrayRef[TAEB::AI::Planar::Plan::Tactical]',
    is      => 'rw',
    default => sub { [] },
    traits  => [qw/TAEB::AI::Planar::Meta::Trait::DontFreeze/],
));
# A plan counts as potentially abandoned if it doesn't strategy-fail
# or tactics-fail or succeed. It is actually marked as abandoned if
# a different plan is selected at the next step and it is potentially
# abandoned. This variable holds the current potentially abandoned
# plan, if there is one. We need to track the most recent tactical
# plan even if it succeeds, if the strategic plan undef's, so we can
# "choose to go in the other direction", but we need to track if it
# succeeded.
has (abandoned_plan => (
    isa     => 'Maybe[TAEB::AI::Planar::Plan]',
    is      => 'rw',
    default => undef,
    traits  => [qw/TAEB::AI::Planar::Meta::Trait::DontFreeze/],
));
has (abandoned_tactical_plan => (
    isa     => 'Maybe[TAEB::AI::Planar::Plan::Tactical]',
    is      => 'rw',
    default => undef,
    traits  => [qw/TAEB::AI::Planar::Meta::Trait::DontFreeze/],
));
has (tactical_plan_succeeded => (
    isa     => 'Bool',
    is      => 'rw',
    default => 0,
    traits  => [qw/TAEB::AI::Planar::Meta::Trait::DontFreeze/],
));
# This list is separate merely for efficiency reasons.
has (tactical_plans => (
    isa     => 'HashRef[TAEB::AI::Planar::Plan::Tactical]',
    is      => 'rw',
    default => sub { {} },
    traits  => [qw/TAEB::AI::Planar::Meta::Trait::DontFreeze/],
));
has (current_tactical_plan => (
    isa     => 'Maybe[TAEB::AI::Planar::Plan::Tactical]',
    is      => 'rw',
    default => undef,
    traits  => [qw/TAEB::AI::Planar::Meta::Trait::DontFreeze/],
));
# Storing plans by the object they refer to speeds up certain
# operations.
has (plan_index_by_object => (
    isa     => 'HashRef[Set::Object]',
    is      => 'rw',
    default => sub { {} },
    traits  => [qw/TAEB::AI::Planar::Meta::Trait::DontFreeze/],
));
# Likewise, by the type of plan.
has (plan_index_by_type => (
    isa     => 'HashRef[Set::Object]',
    is      => 'rw',
    default => sub { {} },
    traits  => [qw/TAEB::AI::Planar::Meta::Trait::DontFreeze/],
));
# Plans sometimes need to store per-AI persistent data, mostly for
# performance reasons. Give them somewhere they can store it without
# having to hack the core AI and without having different plans clash
# with each other.
has (plan_caches => (
    isa     => 'HashRef', # with unknown contents
    is      => 'rw',
    default => sub { {} },
    traits  => [qw/TAEB::AI::Planar::Meta::Trait::DontFreeze/],
));

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
has (_planheap => (
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
    },
    traits  => [qw/TAEB::AI::Planar::Meta::Trait::DontFreeze/],
));
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
	#my @block;

	#while (my ($res, $value) = each %{ $plan->spending_plan }) {
	#    push @block, "$res => $value";
	#}

	#TAEB->log->ai("-> ${\ $plan->name} for $amount - $risk { " . join(", ", @block) .
	#    " }");
	$self->_planheap->insert([$plan, $amount-$risk, 1]);
    } else {
	#TAEB->log->ai("-> ${\ $plan->name} for $amount UNKNOWN RISK");
	$self->_planheap->insert([$plan, $amount, 0]);
    }
}

# The tactics heap. The elements are of the form [tme, dirindex,
# spending_plan, taint, tactic], plus [xfrom, yfrom, lfrom] if
# dirindex is undef; tactic is a tactic index in the lists, or a
# tactical plan object if dirindex is undef.
has (_tacticsheap => (
    isa     => 'Heap::Simple::XS',
    is      => 'rw',
    default => sub {
	return Heap::Simple::XS->new(
	    order => '<',
	    elements => 'Any',
	    dirty => 1,
	);
    },
    traits  => [qw/TAEB::AI::Planar::Meta::Trait::DontFreeze/],
));
# Are we currently doing a full tactical recalculation?
has (full_tactical_recalculation => (
    isa     => 'Bool',
    is      => 'rw',
    default => 1,
    traits  => [qw/TAEB::AI::Planar::Meta::Trait::DontFreeze/],
));
# The tile we were on when we last did tactical mapping. This is
# generally TAEB->current_tile, but not when we're drawing the debug
# view. It's also used to figure out what changed since the last time
# we did tactical routing.
has (tactical_target_tile => (
    isa     => 'Maybe[TAEB::World::Tile]',
    is      => 'rw',
    default => undef,
    traits  => [qw/TAEB::AI::Planar::Meta::Trait::DontFreeze/],
));

# Resources.
has (resources => (
    isa     => 'HashRef[TAEB::AI::Planar::Resource]',
    is      => 'rw',
    default => sub {
	my $self = shift;
	my %resources = ();
	for my $type (resource_names()) {
            $type =~ /([^:]+)$/;
            my $name = $1;
            TAEB->log->ai("Loading resource $name...");
	    $resources{$name} = "TAEB::AI::Planar::Resource::$name"->new;
	}
	return \%resources;
    },
    traits  => [qw/TAEB::AI::Planar::Meta::Trait::DontFreeze/],
));

# The main tactics map.
# This contains all the pathfinding details for each level. Levels
# other than the one we're on are cached (because nothing on them can
# change); this can lead to inaccurate results sometimes when our
# resource levels change (maybe we should invalidate the cache every
# now and then?), but is necessary for decent performance. The current
# level is recalculated every step when the tactical algorithm is
# 'level'; when it's 'chokepoint', only the chokepoint areas that are
# actually affected are updated.
has (main_tactics_map => (
    isa     =>
        'HashRef[ArrayRef[ArrayRef[TAEB::AI::Planar::TacticsMapEntry]]]',
    is      => 'rw',
    default => sub { {} },
    traits  => [qw/TAEB::AI::Planar::Meta::Trait::DontFreeze/],
));
# Tactics maps relative to each chokepoint. The keys are the refaddrs
# to the chokepoint tiles, because Tie::RefHash doesn't seem to be
# working properly in this case.
has (chokepoint_tactics_map => (
    isa     =>
        'HashRef[HashRef[ArrayRef[ArrayRef[TAEB::AI::Planar::TacticsMapEntry]]]]',
    is      => 'rw',
    default => sub { {} },
    traits  => [qw/TAEB::AI::Planar::Meta::Trait::DontFreeze/],
));
# Which chokepoints might be worth looking at for a particular tile. This
# is an overestimate; that is, if a chokepoint might be worth looking at,
# it must definitely be in the set; but it could be in the set even if it
# isn't worth looking at.
has (nearby_chokepoints => (
    isa     => 'HashRef[Set::Object]',
    is      => 'rw',
    default => sub { my %h = (); tie %h, 'Tie::RefHash'; \%h },
    traits  => [qw/TAEB::AI::Planar::Meta::Trait::DontFreeze/],
));
# When (i.e. which aistep) was the chokepoint in question last updated?
has (chokepoint_last_updated => (
    isa     => 'HashRef[Int]',
    is      => 'rw',
    default => sub { {} },
    traits  => [qw/TAEB::AI::Planar::Meta::Trait::DontFreeze/],
));
# undef if looking at the main tactics map; defined if looking at a chokepoint.
has (current_chokepoint => (
    isa     => 'Maybe[TAEB::World::Tile]',
    is      => 'rw',
    traits  => [qw/TAEB::AI::Planar::Meta::Trait::DontFreeze/],
    trigger => sub {
        my ($self, $newcp) = @_;
        return unless defined $newcp;
        # Unfortunately, these can't quite be autovivified.
        if(!defined ($self->chokepoint_tactics_map->{refaddr $newcp})) {
            TAEB->log->ai("Creating a new tactics map for " .
                          $newcp->x . ", " . $newcp->y);
            $self->chokepoint_tactics_map->{refaddr $newcp} = {};
        }
    },
));
sub fetch_tactics_map {
    my $self = shift;
    my $chokepoint = shift;
    return $self->main_tactics_map unless $chokepoint;
    return $self->chokepoint_tactics_map->{refaddr $chokepoint};
}
sub tactics_map {
    my $self = shift;
    return $self->fetch_tactics_map($self->current_chokepoint);
}

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
has (threat_map => (
    isa     => 'HashRef[ArrayRef[ArrayRef[HashRef[Maybe[HashRef[Num]]]]]]',
    is      => 'rw',
    default => sub { {} },
    traits  => [qw/TAEB::AI::Planar::Meta::Trait::DontFreeze/],
));

# When did we last see a monster?
has (last_monster_seen_step => (
    isa     => 'Int',
    is      => 'rw',
    default => 0,
));

# For profiling
has (lasttimeofday => (
    isa     => 'Maybe[ArrayRef]',
    is      => 'rw',
    default => undef,
    traits  => [qw/TAEB::AI::Planar::Meta::Trait::DontFreeze/],
));

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
	$self->abandoned_plan->name ne $self->current_plan->name &&
        !(any {$_->name eq $self->abandoned_plan->name}
             @{$self->current_plan->dependency_path}) &&
        $self->problematic_levitation_step+1 < TAEB->step) {
	# Prevent oscillations; if a plan is abandoned, we don't try it
	# again for a while. (mark_impossible will try a plan twice before
	# suspending it for a while; and remember that dependencies and
	# excursions will mark other plans possible when they succeed.)
	$self->abandoned_plan->abandon;
	TAEB->log->ai("Plan ".$self->abandoned_plan->name.
			       " was abandoned.");
        $self->current_plan->reverse_dependencies
            ->{$self->abandoned_plan->name} = $self->abandoned_plan;
	# More interestingly, we also abandon the tactical plan we
	# were trying, if there is one; even though it quite possibly
	# succeeded! This is to prevent oscillations; if we try the
	# same tactical plan any time soon, we're definitely
	# oscillating and need to try going in the other direction.
	if (defined $self->abandoned_tactical_plan &&
            defined $self->current_tactical_plan &&
            $self->abandoned_tactical_plan->name ne
            $self->current_tactical_plan->name) {
	    $self->abandoned_tactical_plan->abandon;
	    TAEB->log->ai("Tactical plan ".
				   $self->abandoned_tactical_plan->name.
				   " was abandoned.");
            $self->current_tactical_plan->reverse_dependencies
                ->{$self->abandoned_tactical_plan->name} =
                $self->abandoned_tactical_plan;
            # Reinstate the tactical plan if the strategic plan succeeds
            $self->current_plan->reverse_dependencies
                ->{$self->abandoned_tactical_plan->name} =
                $self->abandoned_tactical_plan;
	}
    }
    # Another form of abandonment is tactical plan abandonment within a
    # strategic plan. The above check doesn't detect this (the tactical
    # plans can succeed alternately, cancelling each other out); this one
    # does.
    my $force_tactical_failure = 0;
    if (scalar $self->old_plans > 2 && $self->current_tactical_plan &&
        defined $self->old_tactical_plans->[0] &&
        defined $self->old_tactical_plans->[1] &&
        defined $self->current_plan &&
        defined $self->old_plans->[1] &&
        $self->current_tactical_plan->name eq
        $self->old_tactical_plans->[1]->name &&
        $self->current_plan->name eq $self->old_plans->[1]->name &&
        $self->old_tactical_plans->[0]->name ne
        $self->old_tactical_plans->[1]->name) {
        # We're oscillating between two tactics for the same strategy.
        $self->current_tactical_plan->abandon;
        TAEB->log->ai("Oscillating tactical plan ".
                      $self->current_tactical_plan->name.
                      " was abandoned.");
        $force_tactical_failure = 1;
    }
    unshift @{$self->old_plans}, $self->current_plan;
    unshift @{$self->old_tactical_plans}, $self->current_tactical_plan;
    # Did the plan succeed, or fail, or is it ongoing?
    my $succeeded = undef;
    if (defined $self->current_tactical_plan) {
	# Work out success based on the current tactical plan
	$succeeded = $self->current_tactical_plan->succeeded;
        $succeeded = undef if $force_tactical_failure;
	defined $succeeded and $succeeded and
	    $self->tactical_success_count($self->tactical_success_count+1),
	    TAEB->log->ai("OK, tactic ".
				   $self->current_tactical_plan->name.
				   " worked.", level => 'debug');
	defined $succeeded and !$succeeded and
            $self->problematic_levitation_step+1 < TAEB->step and
	    $self->current_tactical_plan->mark_impossible,
	    TAEB->log->ai("Ugh, tactic ".
				   $self->current_tactical_plan->name.
				   " failed...", level => 'info');
        $self->tactical_plan_succeeded($succeeded ? 0 : 1);
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
            $self->problematic_levitation_step+1 < TAEB->step and
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
    TAEB->log->ai("Time taken for tactical map (algorithm = " .
                  $self->tactical_algorithm_this_turn . "): " .
                  tv_interval($t0,$t1)."s.", level => 'debug');

    # Find our plan for this step.
    my ($plan, $action) = $self->next_plan_action;
    $self->current_plan($plan);
    $t0 = [gettimeofday];
    TAEB->log->ai("Time taken for strategic planning: ".
                  tv_interval($t1,$t0)."s.", level => 'debug');
    $self->lasttimeofday($t0);
    # Work out the currently string.
    my $currently = "{" . $self->tactical_algorithm_this_turn . "} " .
        $self->currently_modifiers .
        join '|', map {$_->shortname} (@{$plan->dependency_path}, $plan);

    # We need to tell if the return value was an action or a tactical
    # plan. We do this by seeing if the class ISA tactical plan; if it
    # is, then it almost certainly isn't an action (and even if it
    # were, we have to do something in that situation, not that it
    # should ever be allowed to happen in the first place).
    if($action && $action->isa('TAEB::AI::Planar::Plan::Tactical')) {
	# It's a tactical plan.
	$self->currently($currently . '-' .
			 $action->shortname);
	$self->current_tactical_plan($action);
	my $inner_action = $action->try;
	return $inner_action if defined $inner_action
                             && !$inner_action->is_impossible;
	# OK, we have an impossible tactic on our hands. The solution
	# here is to repeat the entire plan-finding process without
	# that tactic included. (This shouldn't happen very often, if
	# it does that plan's plan-calculation needs looking at.)
        $self->current_tactical_plan->mark_impossible;
	$self->current_tactical_plan(undef);
	$self->current_plan(undef);
	TAEB->log->ai("Tactical plan ".($action->name).
                      " failed to produce an action, marking it".
                      " as impossible...", level => 'debug');
        $self->full_tactical_recalculation(1);
	@_ = ($self);
	goto &next_action; # tail-recursion
    } elsif (!defined $action || $action->is_impossible) {
        $self->current_plan->mark_impossible;
        $self->current_plan(undef);
	TAEB->log->ai("Plan ".($action->name).
                      " failed to produce an action, marking it".
                      " as impossible...", level => 'debug');
        $self->full_tactical_recalculation(1);
	@_ = ($self);
	goto &next_action; # tail-recursion
    } else {
	$self->currently($currently);
	$self->current_tactical_plan(undef);
	return $action;
    }
}

# The actual AIing.
sub next_plan_action {
    my $self = shift;
    my $action = undef;
    my $aistep = $self->aistep;
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
#    for my $ref (@refs) {
#	my $addr = refaddr($ref);
#	/\[$addr\]/ and $self->plans->{$_}->validate for keys %{$self->plans};
#    }
    # Create plans for items and map features, if necessary.
    for my $item (TAEB->inventory->items) {
	$self->get_plan("InventoryItemMeta",$item)->validate;
    }
    for my $mon (TAEB->current_level->monsters) {
	$self->get_plan("MonsterMeta",$mon)->validate;
    }
    for my $item (TAEB->current_level->items) {
	$self->get_plan("GroundItemMeta",$item)->validate;
    }
    TAEB->current_level->each_tile(sub {
	my $tile = shift;
	# Interesting tiles have Investigate as a metaplan. These are
	# tiles on which we know there are items, but not what.
	$tile->is_interesting and
            $self->get_plan("Investigate",$tile)->validate;
    });
    # Various interesting sorts of terrain get TerrainMeta.
    my $tbt = TAEB->current_level->tiles_by_type;
    for my $tile (@{$tbt->{'fountain'}},
                  @{$tbt->{'stairsup'}}, @{$tbt->{'stairsdown'}}) {
        $self->get_plan("TerrainMeta",$tile)->validate;
    }
    $self->get_plan("CharacterMeta")->validate;
    $self->validitychanged(1);
    while ($self->validitychanged) {
        # Spawn only from valid plans; repeat until there's no change
        # in validity.
        $self->validitychanged(0);
        $_->validity and $_->maybe_planspawn($aistep)
            for values %{$self->plans};
    }
    # Delete any plans which are still invalid.
    for my $planname (keys %{$self->plans}) {
	delete $self->plans->{$planname}
#         TAEB->log->ai("Eliminating invalid plan $planname",
#                       level => 'debug'))
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
    my $majorplan = $self->overall_plan;
    my @illegal_plans = ();
    if (defined $self->abandoned_plan) {
        @illegal_plans = (@illegal_plans,
                          @{$self->abandoned_plan->uninterruptible_by});
    }
    if (defined $self->abandoned_tactical_plan &&
        !$self->tactical_plan_succeeded) {
        @illegal_plans = (@illegal_plans,
                          @{$self->abandoned_tactical_plan->uninterruptible_by});
    }
    if (defined $self->old_plans->[0]) {
        @illegal_plans = (@illegal_plans,
                          @{$self->old_plans->[0]->unfollowable_by});
    }
    if (defined $self->old_tactical_plans->[0]) {
        @illegal_plans = (@illegal_plans,
                          @{$self->old_tactical_plans->[0]->unfollowable_by});
    }
    $self->currently_modifiers('');

    # If we had trouble doing what we wanted to do last turn due to
    # levitation, we're almost certainly going to have the same trouble
    # this turn. So, we want to unlevitate above all else.
    # TODO: Is this check in the wrong place? It's sort-of like a
    # threat, except that it's strategic rather than tactical.
    TAEB->log->ai("Trying to unlevitate before doing anything else"),
        $self->add_capped_desire($self->get_plan('Unlevitate'), 1.1e8)
            if $self->problematic_levitation_step+1 >= TAEB->step;

    while (1) {
	my $desire;
	$plan = undef;
	PLANLOOP: {
	    my $heapentry = $self->_planheap->extract_first;
	    #TAEB->log->ai("<- ${$heapentry}[0]");
	    my $withrisk;
	    # If there was no result, bail out to the block that tries
	    # to manipulate things to give us a result.
	    (($plan=undef), last) unless defined $heapentry;
	    ($plan,$desire,$withrisk) = @$heapentry;
	    # Likewise, bail if all plans are undesirable.
	    (($plan=undef), last) if $desire <= 0;
            # Ignore this plan if it's invalid. (Such plans can still
            # generate desirability, due to the timing in the code
            # above, even if they've been deleted from the plan list.)
            redo unless $plan->validity;
	    # If this heap entry was calculated without taking risk
	    # into account, but we now have more accurate figures,
	    # ignore in favour of those (lower) figures.
	    redo if $plan->risk_valid_on_step == $aistep && !$withrisk;
            # If this plan is illegal (e.g. because it interrupts a
            # plan that it isn't allowed to interrupt), ignore it.
            if (!($self->abandoned_plan && $self->abandoned_plan == $plan) &&
                !($self->abandoned_tactical_plan &&
                  $self->abandoned_tactical_plan == $plan)) {
              $plan->name =~ /^$_(?:\[.*)?/ and
                  TAEB->log->ai("Ignoring " . $plan->name .
                                " because it's an illegal interruption"),
                  redo PLANLOOP for @illegal_plans;
            }
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
                $self->aistep(++$aistep); # will this break anything?
                $self->threat_check;
                $self->update_tactical_map;
		$self->_planheap->clear;
		%planstate = ();
		$self->analysis_window($self->analysis_window / 2)
		    if $self->analysis_window >= 2;
	    }
	    $self->add_capped_desire($self->get_plan($majorplan),
				     1e8);
	    next;
	}
	$bestplanname = $plan->name;
	# The plan needs to know how raw-desirable it is, and how
	# desirable if risk is accounted for, so it can spread
	# desirability (from calculate_risk or spread_desirability).
	$plan->desire($desire +
                      ($plan->risk_valid_on_step == $aistep ? $plan->risk : 0));
	$plan->desire_with_risk($desire);
	# If the plan has zero difficulty and uncalculated risk,
	# calculate its risk (possibly spreading desire onto things
	# that would make it less risky).
	if ($plan->difficulty <= 0 &&
	    $plan->risk_valid_on_step != $aistep) {
#            local $Data::Dumper::Indent = 0; # for debugging
	    $plan->risk_valid_on_step($aistep);
	    $plan->spending_plan({});
	    $plan->risk($plan->calculate_risk);
	    # Some more debugging lines that I seem to use a lot
#            TAEB->log->ai(
#                "Risk of $bestplanname calculated at ".$plan->risk);
#            TAEB->log->ai("Desire was $desire");
#            TAEB->log->ai("Spending plan is ".Dumper($plan->spending_plan));
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
            # TAEB->log->ai("Trying plan $bestplanname..."); # debug
	    $action = $plan->try;
	    last if $action;
	}
	# Seems it was impossible. Oh well...
	$plan->spread_desirability;
    }
    $self->analysis_window($self->analysis_window + 1)
	if $self->analysis_window < 50;
    TAEB->log->ai("Plan $bestplanname (risk = " . (join '|',%{$plan->spending_plan})
                  . " = " . $plan->risk
                  . ") thinks it's possible, enacting it.", level => 'info');
    return ($plan, $action);
}

has (last_tactical_recalculation => (
    is => 'rw',
    isa => 'Int',
    default => 0,
));
has (tactical_algorithm_this_turn => (
    is => 'rw',
    isa => 'Str', # TODO: enum
    default => 'level',
));

# Tiles that have had their type changed since last time we did a
# chokepoint routing.
has (chokepoint_examine_tiles => (
    is => 'rw',
    isa => 'Set::Object',
    default => sub { return Set::Object->new(); },
    traits  => [qw/TAEB::AI::Planar::Meta::Trait::DontFreeze/],
));
# Which chokepoints existed last time we did a chokepoint routing.
has (old_chokepoint_set => (
    is => 'rw',
    isa => 'Set::Object',
    default => sub { return Set::Object->new(); },
    traits  => [qw/TAEB::AI::Planar::Meta::Trait::DontFreeze/],
));
# Do we need/want to recalculate the whole chokepoint map?
has (need_full_chokepoint_recalc => (
    is => 'rw',
    isa => 'Bool',
    default => 1,
    traits  => [qw/TAEB::AI::Planar::Meta::Trait::DontFreeze/],
));

# Matches the order in T::A::P::P::Tactical, TAEB::Util::deltas
use constant _dindex_to_vi => [qw/y b u n h l k j/];

sub update_tactical_map {
    my $self = shift;
    my $curlevel = TAEB->current_level;
    my $curlevelra = refaddr($curlevel);
    my $algorithm = $self->tactical_algorithm;
    my $ftr = 1;
    my $tct = TAEB->current_tile;
    my $last_ttt = $self->tactical_target_tile;
    my $aistep = $self->aistep;
    my $map = $self->tactics_map;
    my $thmap = $self->threat_map;
    $ftr = $last_ttt->level != $curlevel if $last_ttt;

    # Do a tactical recalc every 100 turns, to prevent us getting stuck
    # if there's a monster next to the stairs. TODO: This is a hack,
    # a better solution is really needed.
    if (TAEB->turn > $self->last_tactical_recalculation + 100 ||
        $algorithm eq 'world') {
        $ftr = 1;
    }
    if ($algorithm eq 'chokepoint' && $self->threat_count) {
        # Threats cause far too much updating of the tactical map;
        # we'd need to throw out the submaps pretty much every turn,
        # which would defeat the entire point of using chokepoint in
        # the first place. So use level instead when that happens.
        $algorithm = 'level';
    }
    if ($algorithm eq 'chokepoint' && $curlevel->monster_count) {
        # Even non-threatening monsters violate the assumptions that
        # chokepoint makes (that is, that tiles won't change routing
        # properties unless they change type). TODO: Handle I glyphs
        # somehow? They aren't really monsters.
        $algorithm = 'level';
    }
    if ($algorithm eq 'chokepoint' &&
        TAEB->inventory->find(['pick-axe', 'dwarvish mattock'])) {
        # No mathematical reason not to use chokepoint here; it's just
        # that with that amount of routing involved, level is just faster.
        # TODO: I'm pretty sure there's an algo faster than either if
        # tunneling is allowed...
        $algorithm = 'level';
    }
    # TODO: get chokepoint working with the new system
    $algorithm eq 'chokepoint' and $algorithm = 'level';
    $self->full_tactical_recalculation and $ftr = 1;

    # If we've changed level, reset all the TMEs.
    if ($ftr) {
        TAEB->log->ai("Resetting all TMEs...");
        for my $levelgroup (@{TAEB->dungeon->levels}) {
            for my $level (@$levelgroup) {
                $map->{refaddr $level} = [];
                my $levelmap = $map->{refaddr $level};
                # MAGIC NUMBER alert! Should this be centralised somewhere?
                $levelmap->[$_] = [] for 0..79;
            }
        }
        $self->full_tactical_recalculation(1);
        $self->need_full_chokepoint_recalc(1);
    }
    $self->tactical_target_tile(TAEB->current_tile);
    # TODO: Can we get around calling this when not chokepoint routing?
    $self->locate_chokepoints;

    # We iterate from several different routing points.
    # For 'level' and 'world' algorithms, we just use the current tile.
    # For 'chokepoint', we iterate from every chokepoint that needs a
    # route recalculation (or simply from every chokepoint during an ftr);
    # but we taint at each other chokepoint. The effect is that the map is
    # divided into regions based on which chokepoints could possibly be the
    # best ones to route there from (i.e. we know all others are suboptimal);
    # then we can update it just a bit at a time.
    my @seed_locations = ();
    if ($algorithm eq 'chokepoint' && !$ftr) {
        if ($self->need_full_chokepoint_recalc) {
            @seed_locations = $self->chokepoint_set->elements;
            $self->need_full_chokepoint_recalc(0);
        } else {
            # Look for new chokepoints, and chokepoints nearby updated
            # squares and their neighbours. This is likely to be
            # degenerate half the time, which is exactly what we want;
            # but even a drastic change in the level should be handled
            # correctly.
            my $locset = Set::Object->new();
            my $cetset = $self->chokepoint_examine_tiles;
            # Look for chokepoints that have recently been removed.
            for my $oldcp ($self->old_chokepoint_set->elements) {
                 ($self->chokepoint_map->{refaddr $oldcp} // 0) == -2
                     and $self->old_chokepoint_set->delete($oldcp);
            }
            for my $ctile ($cetset->elements,
                           $self->old_chokepoint_set->elements) {
                next unless $cetset->includes($ctile);
                $ctile->each_adjacent_inclusive(sub {
                    my $tile = shift;
                    my $cpset = $self->nearby_chokepoints->{$tile};
                    $cpset and $cpset->size and $locset->insert($cpset->elements);
                    ($self->chokepoint_map->{refaddr $tile} // 0) == -2
                        and $locset->insert($tile);
                    $cetset->delete($tile);
                });
            }
            @seed_locations = $locset->elements;
        }
        $self->chokepoint_examine_tiles->clear;
        $self->old_chokepoint_set->clear;
        $self->old_chokepoint_set->insert($self->chokepoint_set->elements);
        # Chokepoints we're standing on are routed a bit differently.
        # So if we're standing on a chokepoint, mark it for regeneration
        # next chokepoint routing.
        ($self->chokepoint_map->{refaddr(TAEB->current_tile)} // 0) == -2
            and $self->chokepoint_examine_tiles->insert(
                TAEB->current_tile);
    }

    # For efficiency, we cache the tactical plan, and its spending
    # plan, of moving onto each square in its TME. This is typically
    # symmetrical, but can be different in each direction. This is
    # also where the tactical plans first come in; we use MoveTo to
    # tag a TME with the appropriate tactics for moving there.
    my $iterator = $self->full_tactical_recalculation
        ? "each_tile" : "each_changed_tile_and_neighbors";
    # Iterate over the current level or whole map as appropriate.
    for my $levelgroup (@{$ftr ? TAEB->dungeon->levels :
                              [[TAEB->current_level]]}) {
        for my $level (@$levelgroup) {
            # Note that for this to work, it critically requires TAEB
            # monster objects to reflect monster /observations/, not
            # monster memory, so that we don't try to ScareMonster a
            # blank space because the monster memory expired but
            # each_changed_tile_and_neighbours didn't tell us because
            # the tile hadn't changed.
            my $levelmap = $map->{refaddr $level};
            $level->$iterator(sub {
                my $tile = shift;
                my $tx = $tile->x;
                my $ty = $tile->y;
                my $esp = [];
                my $tme = $levelmap->[$tx]->[$ty] = {
                    # prevtile, prevlevel stuff is all undef
                    step => -1,
                    considered => -1,
                    # risk, level_risk should be set before being used
                    # so we leave them undef so we get a warning if
                    # they aren't
                    other_tactics => [],
                    entry_tactics => [[],[],[],[],[],[],[],[]],
                    entry_spending_plans => [[]],
                    is_symmetrical => 1,
                    tile_x => $tx,
                    tile_y => $ty,
                    tile_level => $level,
                    make_safer_plans => {},
                    # hasn't been checked, leave checked_at_desire undef
                    taint => 0,
                    source => 'uninitialised',
                };
                bless $tme, "TAEB::AI::Planar::TacticsMapEntry";
                $self->get_tactical_plan("MoveTo", [$level,$tx,$ty])->
                    check_possibility($tme);
                $self->get_tactical_plan("MoveFrom", [$level,$tx,$ty])->
                    check_possibility($tme);
            });
        }
    }

    # Actually calculate all the TMEs we're going to calculate this
    # step. This depends on the algorithm, as to whether it's all the
    # TMEs in the world, TMEs on the current level, or TMEs near
    # changed chokepoints.
    my $clu = $self->chokepoint_last_updated;
    for my $iter ('tct', @seed_locations) {
        my $is_tct = !blessed $iter;
        my $seed = $is_tct ? $tct : $iter;
        # Dijkstra's algorithm is used to flood the level with pathfinding
        # data. The heap contains TacticsMapEntry elements.
        my $heap = $self->_tacticsheap;
        $heap->clear;
        # Initialise. We can path to the square we're on without issue and
        # without risk (as it's a NOP).
        $self->tactical_target_tile($seed);
        $self->current_chokepoint($is_tct ? undef : $seed);
        $is_tct or $clu->{refaddr $seed} = $aistep;
        my $seedx = $seed->x;
        my $seedy = $seed->y;
        my $nearby = $self->nearby_chokepoints;
        my $seedtme = $map->{refaddr $seed->level}->[$seedx]->[$seedy];
#        TAEB->log->ai("Doing routing from $seedx, $seedy on map $map");
        my $untainted = 1; # number of untainted TMEs
        $seedtme->{$_} = undef
            for qw/prevtile_level  prevtile_x  prevtile_y
                   prevlevel_level prevlevel_x prevlevel_y/;
        $seedtme->{'step'} = -1;
        $seedtme->{'risk'} = {}; $seedtme->{'level_risk'} = {};
        $seedtme->{'make_safer_plans'} = {};
        $heap->key_insert(0, [$seedtme, undef, {}, 0,
                              $self->get_tactical_plan('Nop'),
                              $seedx, $seedy, $seed->level]);
        while ($untainted) {
            my $tmedir = $heap->extract_top;
            my $tme    = $tmedir->[0];
            my $taint  = $tmedir->[3];
            my $tx     = $tme->{'tile_x'};
            my $ty     = $tme->{'tile_y'};
            my $tl     = $tme->{'tile_level'};
#            TAEB->log->ai("Current untainted count is $untainted");
            $untainted-- unless $taint;
            # If we're off the level, just ignore this TME, to avoid
            # updating the entire dungeon every step, unless we just
            # changed level.
            # The whole dungeon /is/ updated when we change level.
            next if refaddr($tl) != $curlevelra && !$ftr;
            # If we've already found an easier way to get here, ignore
            # this method of getting here.
            next if $tme->{'step'} == $aistep;
            # This is the best way to get here; add it to the tactical
            # map, then spread possibility from it via the MoveFrom
            # metaplan. We do this by updating the TME; what needs
            # changing are the previous x/y/l values (on tiles/levels),
            # and the spending plan, as well as marking the TME as
            # up-to-date.
            my $dir    = $tmedir->[1];
            my $sp     = $tmedir->[2]; # total risk for the move
            my %risk   = %$sp;
            my $tindex = $tmedir->[4];
            my $threats_added = 0;

            my ($px, $py, $pl, $tactic, $oldtme);

#            TAEB->log->ai("Considering move ".$self->planname("",$tmedir));

            if (defined $dir) {
                # We're moving one step within the level.
                my ($dx, $dy) = @{[deltas]->[$dir]};
                $px = $tx - $dx; # if moving (+1,+1), we're coming from (-1,-1)
                $py = $ty - $dy;
                $pl = $tl;

                $oldtme = $map->{refaddr $pl}->[$px]->[$py];

                # For such tactics, the calling convention is to give the
                # TME coordinates we're moving /to/, and the direction the
                # move is made in.
                $tactic = $self->get_tactical_plan(
                    $tme->{'entry_tactics'}->[$dir]->[$tindex],
                    [$tl, $tx, $ty, _dindex_to_vi->[$dir]]);

                # Add cost from threats on this tile onto the spending
                # plan, because it wasn't done earlier. (This can be
                # marginally incorrect in situations where a threat on a
                # square would control which route was used to reach it
                # due to balancing resources; I'm not too fussed about
                # that, though.)
                my %msp = %{dclone($oldtme->{'make_safer_plans'})};
                my $oldthme = $thmap->{refaddr $pl}->[$px]->[$py];
                my $newthme = $thmap->{refaddr $tl}->[$tx]->[$ty];
                my $timetohere = $sp->{'Time'} // 0;
                my $timethisstep = $tme->{'entry_spending_plans'}->
                    [$tme->{'is_symmetrical'} ? 0 : $dir]->[$tindex]
                    ->{'Time'} // 0;
                for my $iter (0 .. ($timethisstep > 1 ? 1 : 0)) {
                    my $thme = $iter ? $oldthme : $newthme;
                    # TODO: Handle threats on different levels sanely
                    if ($iter  && $pl == $curlevel ||
                        !$iter && $tl == $curlevel) {
                        for my $p (keys %$thme) {
                            defined($thme->{$p}) or next;
                            $p eq 'stairsmod' and next;
                            # Ignore threats that won't get here in time.
                            my ($turns, $reductionplan) = split / /, $p;
                            $turns > $timetohere and next;
                            $threats_added++;
                            my $riskmul = $timetohere - $turns;
                            if ($iter) {
                                $riskmul = $timethisstep - 1 if
                                    $riskmul > $timethisstep - 1;
                            } else {
                                $riskmul -= $timethisstep - 1
                                    if $timethisstep > 1;
                                $riskmul = 1 if $riskmul < 1;
                            }
                            my $threatrisk = $thme->{$p};
                            $msp{$reductionplan}->{$_} //= 0 for keys %$threatrisk;
#                            $msp{$reductionplan}->{$_} > ($risk{$_}//0) ? TAEB->log->ai("MSP already saves more than it costs: $_ $risk{$_} ".$msp{$reductionplan}->{$_}." oldrisk ".$oldtme->{'risk'}->{$_}." oldmsp ".$oldtme->{'make_safer_plans'}->{$reductionplan}->{$_}." at ($tx,$ty)") : TAEB->log->ai("MSP already saves $_ ".$msp{$reductionplan}->{$_}. " risk ".($risk{$_}//0)." at ($tx,$ty)") for keys %$threatrisk;
                            $risk{$_} += $$threatrisk{$_} * $riskmul
                                for keys %$threatrisk;
                            $msp{$reductionplan}->{$_} +=
                                $$threatrisk{$_} * $riskmul
                                for keys %$threatrisk;
#                            $msp{$reductionplan}->{$_} > ($risk{$_}//0) ? TAEB->log->ai("MSP saves more than it costs: $_ $risk{$_} ".$msp{$reductionplan}->{$_}." oldrisk ".$oldtme->{'risk'}->{$_}." oldmsp ".$oldtme->{'make_safer_plans'}->{$reductionplan}->{$_}." at ($tx,$ty)") : TAEB->log->ai("MSP saves $_ ".$msp{$reductionplan}->{$_}. " risk ".($risk{$_}//0)." at ($tx,$ty)") for keys %$threatrisk;
                        }
                    }
                }
                $tme->{'make_safer_plans'} = \%msp;
            } else {
                $px = $tmedir->[5];
                $py = $tmedir->[6];
                $pl = $tmedir->[7];
                $oldtme = $map->{refaddr $pl}->[$px]->[$py];
                # We're given an entire, heavyweight tactical plan object.
                # This is, fortunately, rare.
                # TODO: Threats? We'd need some hint as to how the plan
                # in question worked.
                $tactic = $tindex;
                $tme->{'make_safer_plans'} = $oldtme->{'make_safer_plans'};
            }

            $tme->{'prevtile_level'} = $pl;
            $tme->{'prevtile_x'} = $px;
            $tme->{'prevtile_y'} = $py;
            $tme->{'step'} = $aistep;
            # considered should already be right
            $tme->{'risk'} = \%risk;
            $tme->{'tactic'} = $tactic; # TODO: defer this into tme_from_tile?
            $tme->{'taint'} = $taint; # TODO: is this necessary?
            $tme->{'source'} = $ftr ? 'world' : 'level';

            if ($ftr) {
                if ($pl == $tl) {
                    if ($px != $tx || $py != $ty) {
                        die 'Intralevel path in undefined direction'
                            unless defined $dir;
                        $tme->{'prevlevel_level'} = $oldtme->{'prevlevel_level'};
                        $tme->{'prevlevel_x'} = $oldtme->{'prevlevel_x'};
                        $tme->{'prevlevel_y'} = $oldtme->{'prevlevel_y'};
                        # The spending plan in $tmedir is the /total/ spending
                        # plan. We want the one-step spending plan to update
                        # lrisk, so we grab it from the TME itself.
                        # TODO: What if this is nondirectional?
                        my %lrisk = %{$tme->{'entry_spending_plans'}
                                      ->[$tme->{'is_symmetrical'} ? 0 : $dir]
                                      ->[$tindex]};
                        $lrisk{$_} += $oldtme->{'level_risk'}->{$_}
                            for keys %{$oldtme->{'level_risk'}};
                        $tme->{'level_risk'} = \%lrisk;
                    } # otherwise it's a NOP, with already updated risks, etc
                } else {
                    $tme->{'prevlevel_level'} = $pl;
                    $tme->{'prevlevel_x'} = $px;
                    $tme->{'prevlevel_y'} = $py;
                    # We don't have the spending plan between the levels
                    # stored anywhere right now, so we need to subtract.
                    my %lrisk = %{$tme->{'risk'}};
                    $lrisk{$_} -= $oldtme->{'risk'}->{$_}
                        for keys %{$oldtme->{'risk'}};
                    $tme->{'level_risk'} = \%lrisk;
                }
            }

#            TAEB->log->ai("Locking in TME " . $tme->{'tactic'}->name . " at $tx, $ty");
            # Maybe start tainting?
            if ($algorithm eq 'chokepoint' && !$ftr) {
                my $tmetile = $tl->at($tx, $ty);
                if (!$taint && ($seedx != $tx || $seedy != $ty) && 
                    ($self->chokepoint_map->{refaddr $tmetile} // 0) == -2) {
                    $taint = 1;
#                    TAEB->log->ai("Starting to taint at ($tx, $ty) " .
#                                  "[seed = ($seedx, $seedy)]");
                }
                if (!$is_tct) {
                    $nearby->{$tmetile} //= Set::Object->new();
                    if ($taint) {
                        $nearby->{$tmetile}->delete($seed);
                    } else {
                        $nearby->{$tmetile}->insert($seed);
                    }
                }
            }

            # Now spread to neighbours.
            # The rules are: each adjacent tile for which we have a
            # plan to move there is checked. If it already has a TME
            # locked in for the step, skip it; if it already has a TME
            # being considered and is symmetrical, skip it; otherwise
            # calculate the spending plans for each method of moving
            # there, and enheap the cheapest.
            for my $d (0 .. 7) {
                my ($nx, $ny) = @{[deltas]->[$d]};
                $nx += $tx; $ny += $ty;
#                TAEB->log->ai("Checking direction $d ($nx,$ny)");
                $nx < 0 || $nx > 79 || $ny < 1 || $ny > 21 and next;
                my $ntme = $map->{refaddr $tl}->[$nx]->[$ny];
                my $d2 = $d;
                my $sym = 0;
                $d2 = 0, $sym = 1 if $ntme->{'is_symmetrical'};
#                if (!$sym) {TAEB->log->ai("Routing asymmetrical ($nx, $ny)");}
                !scalar($ntme->{'entry_tactics'}->[$d]) and next;
                $ntme->{'step'} == $aistep and next;
                $sym && $ntme->{'considered'} == $aistep and next;
                # If this tile has threats, another tile might make
                # a better route to the next tile.
                $ntme->{'considered'} = $aistep unless $threats_added;
#                TAEB->log->ai("It isn't locked in yet.");

                my $ti = 0;
                my $bestcost = '+inf';
                my $bestsp = undef;
                my $besti = undef;
#                if (!$sym) {TAEB->log->ai("About to count spending plans (d2 = $d2)");
#                TAEB->log->ai(Dumper($ntme));}
                for my $nesp (@{$ntme->{'entry_spending_plans'}->[$d2]}) {
#                    if (!$sym) {TAEB->log->ai("On spending plan $ti");}
                    my %nsp = %risk;
                    $nsp{$_} += $$nesp{$_} for keys %$nesp;
                    my $cost = numerical_risk_from_spending_plan(\%nsp);
                    if ($cost < $bestcost) {
                        $bestcost = $cost;
                        $besti = $ti;
                        $bestsp = \%nsp;
                    }
                    $ti++;
                }
                if (defined $bestsp) {
                    # A little trick; we want to favour orthogonal
                    # moves over diagonal, but don't want to break
                    # symmetry. So we add a tiny amount onto the cost
                    # of diagonal moves here, so that all it affects
                    # is the order of unheaping, and the modified
                    # value is not seen by anything else.
                    $heap->key_insert(
                        $bestcost + ($d < 4 ? 1e-10 : 0),
                        [$ntme, $d, $bestsp, $taint, $besti]);
                    !$taint and $untainted++;
                }
            }
            # Complex plans: plans that don't move one square
            # sideways. This is much "simpler" than directional plans,
            # but much less efficient; it is, however, the unusual
            # case, and won't be called much, so that's less of an
            # issue. This doesn't look at nor update considered,
            # because to do so would break the optimisation on
            # directional routing.
            for my $op (@{$tme->{'other_tactics'}}) {
                # We can make no assumptions, so recalculate risk.
#                TAEB->log->ai("Checking complex tactic ".$op->name);
                next unless $op->is_possible($tme);
                next if $op->difficulty;
                $op->next_plan_calculation;
                $op->spending_plan({});
                $op->calculate_risk($tme);
                my %nsp = %{$op->spending_plan};
                $nsp{$_} += $risk{$_} for keys %risk;
                my $cost = numerical_risk_from_spending_plan(\%nsp);
                my $ttile = $op->tile;
                my ($nx, $ny, $nl) = ($ttile->x, $ttile->y, $ttile->level);
                my $ntme = $map->{refaddr $nl}->[$nx]->[$ny];
#                TAEB->log->ai("Enheaping complex tactic ".$op->name.
#                              " at cost $cost");
                $heap->key_insert(
                    $cost,
                    [$ntme, undef, \%nsp, $taint, $op,
                     $tx, $ty, $tl]);
                $taint or $untainted++;
            }
        }
        # Mark the seed as having no previous TME.
        $seedtme->{$_} = undef
            for qw/prevtile_level  prevtile_x  prevtile_y
                   prevlevel_level prevlevel_x prevlevel_y/;
    }

    # Chokepoint routing requires an extra step.
    $self->current_chokepoint(undef); # back to the main map
    if ($algorithm eq 'chokepoint' && !$ftr) {
        # Now we've done local routing, we need to route globally.
        # We route just over the set of chokepoints, using Dijkstra;
        # we need to calculate an up-to-date TME for each of them,
        # relative to the current tile. (Note that this is pointless
        # during ftr, as we already have a TME for each chokepoint as
        # a side-effect of doing that.) We again use the tacticsheap,
        # against adding TMEs; these are all current-tile-relative
        # TMEs, calculated from the chokepoint TMEs.
        TAEB->log->ai("Starting global chokepoint routing...");
        my $heap = $self->_tacticsheap;
        my $map = $self->tactics_map;
        @seed_locations = $self->chokepoint_set->elements;
        $heap->clear;
        # This TME is definitely up to date; it's the Nop tile from
        # the main routing.
        $heap->insert($self->tme_from_tile($tct));
        while ($heap->count) {
            my $tme = $heap->extract_top;
            my $tx  = $tme->{'tile_x'};
            my $ty  = $tme->{'tile_y'};
            my $tl  = $tme->{'tile_level'};
            my $row = $map->{refaddr $tl}->[$tx];
            my $is_tct = $tx == $tct->x && $ty == $tct->y;
            # If this chokepoint's already been routed to faster, no
            # point in recalculating. However, ignore tainted routes
            # in this (i.e. routes to one chokepoint via another);
            # this is because those extra links will just slow down
            # routing given that an exactly equal link exists anyway.
            next if exists $row->[$ty] && $row->[$ty]->{'step'} == $aistep
                 && $row->[$ty]->{'source'} eq 'globalchokepoint';
            # The Nop on the starting position mustn't be overwritten. This
            # setting of the source is a no-op for all other locations, but
            # very important for $tct if it happens to be on a chokepoint.
            $tme->{'source'} = 'globalchokepoint';
            # Place this TME on the main tactical map.
            $row->[$ty] = $tme;
#            TAEB->log->ai("Adding a global routing TME at $tx, $ty");
            # Find all chokepoints that this one routes to in an
            # untainted fashion.
            my $cptile = $tl->at($tx,$ty);
            my $cpmap = $self->fetch_tactics_map(
                $is_tct ? undef : $cptile);
            die "Chokepoint $cptile should have been mapped and wasn't"
                unless $cpmap;
            $cpmap = $cpmap->{refaddr $tl};
            my $cpclu = $is_tct ? $aistep : $clu->{refaddr $cptile};
            for my $seed (@seed_locations) {
                my $stme = $cpmap->[$seed->x]->[$seed->y];
                next unless defined $stme;
                if ($stme->{'step'} >= $cpclu && !$stme->{'taint'}) {
                    # Calculate an updated main map TME for $stme
                    # via $tme. The resulting TME is a cross between
                    # the two originals.
                    my %risk = %{$tme->{'risk'}};
                    my $stmerisk = $stme->{'risk'};
                    $risk{$_} += $stmerisk->{$_} for keys %$stmerisk;
                    my $newtme = {
                        prevtile_level   => $tl,
                        prevtile_x       => $stme->{'prevtile_x'},
                        prevtile_y       => $stme->{'prevtile_y'},
                        risk             => \%risk, # total of the two
                        tactic           => $stme->{'tactic'},
                        tile_x           => $stme->{'tile_x'},
                        tile_y           => $stme->{'tile_y'},
                        tile_level       => $tl,
                        step             => $aistep,
                        considered       => $aistep,
                        source           => 'globalchokepoint',
                        make_safer_plans => {}, # no threats allowed!
                    };
                    bless $newtme, "TAEB::AI::Planar::TacticsMapEntry";
                    $heap->insert($newtme);
#                    TAEB->log->ai("Heaping a global routing TME at " .
#                        $stme->{'tile_x'} . ", " . $stme->{'tile_y'});
                }
            }
        }
    }
    $ftr and $self->last_tactical_recalculation(TAEB->turn);
    $self->full_tactical_recalculation(0);
    $self->tactical_target_tile($tct);
    $self->tactical_algorithm_this_turn($ftr ? 'world' : $algorithm);
}

# A map of chokepoints. The values are set as follows (using inherent
# walkability, i.e. ignoring monsters and boulders):
#  0 for an unroutable tile, or tile with no routable orthogonal neighbours
#  1 for a routable tile with 1 routable orthogonal neighbour
#  2 for a routable tile with 2 opposite routable orthogonal neighbours
#       or where 2 adjacent are routable, with the tile between unroutable
#  3 for a routable tile with 3 or more routable neighbours
#       or where 2 adjacent are routable, with the tile between also routable
# -2 for a tile that would be marked 2, but has a 3 as an orthogonal neighbour
has (chokepoint_map => (
    is => 'rw',
    isa => 'HashRef[Int]',
    default => sub { {} },
    traits  => [qw/TAEB::AI::Planar::Meta::Trait::DontFreeze/],
));
# A set of chokepoints. This is indexing the map, and contains the same
# information.
has (chokepoint_set => (
    is => 'rw',
    isa => 'Set::Object',
    default => sub { Set::Object->new(); },
    traits  => [qw/TAEB::AI::Planar::Meta::Trait::DontFreeze/],
));

# Find the locations of the chokepoints on the current level.
sub locate_chokepoints {
    my $self = shift;
    my $iterator = $self->full_tactical_recalculation
        ? "each_tile" : "each_changed_tile_and_neighbors";
    my $tcl = TAEB->current_level;
    my $curmap = $self->chokepoint_map;
    $iterator eq 'each_tile' and $self->chokepoint_set->clear;
    $tcl->$iterator(sub {
        my $tile = shift;
        if (($curmap->{refaddr $tile} // 0) == -2) {
            $self->chokepoint_set->delete($tile);
        }
        $curmap->{refaddr $tile} = 0, return
            unless $self->tile_eventually_walkable($tile,0);
        my $routable_neighbours = 0;
        my $last_routable_neighbour = undef;
        $tile->each_orthogonal(sub {
            my $adj = shift;
            if($self->tile_eventually_walkable($adj,0)) {
                $routable_neighbours++;
                if ($routable_neighbours == 2) {
                    if ($adj->x != $last_routable_neighbour->x &&
                        $adj->y != $last_routable_neighbour->y) {
                        my $between = $tcl->at(
                            $last_routable_neighbour->x+$adj->x-$tile->x,
                            $last_routable_neighbour->y+$adj->y-$tile->y);
                        if($self->tile_eventually_walkable($between,0)) {
                            $routable_neighbours++;
                        }
                    }
                }
                $last_routable_neighbour = $adj;
            }
        });
        $routable_neighbours = 3 if $routable_neighbours > 3;
        $curmap->{refaddr $tile} = $routable_neighbours;
#D#        TAEB->log->ai("Placing $routable_neighbours at " . ($tile->x) . ", " .
#D#                      ($tile->y));
    });
    # Not quite perfect, but close enough, especially given that chokepoint
    # locations are heuristic anyway. (We'd expand the iteration one more
    # square to ensure that we caught all cases, but an adjacent 2 becoming
    # a 3 is kind-of unlikely, and anyway we'll notice if we ever walk past
    # the square or change level, or in 100 turns.)
    $tcl->$iterator(sub {
        my $tile = shift;
        return unless $curmap->{refaddr $tile} == 2;
        $tile->each_orthogonal(sub {
            my $adj = shift;
            my $val = $curmap->{refaddr $adj} // 0;
            if ($val == 3) {
                $curmap->{refaddr $tile} = -2;
                $self->chokepoint_set->insert($tile);
                # Is this a new chokepoint?
                defined $self->fetch_tactics_map($tile)
                    or $self->chokepoint_examine_tiles->insert($tile);
            }
        });
    });
}

# Add a threat to the threat map.
sub add_threat {
    my $self = shift;
    my $planname = shift;
    my $danger = shift; # a hashref resource=>amount
    my $tile = shift;
    my $relspeed = shift;
    my $movetype = shift;
    my $nomark_tile = shift;
    my $adjonly = shift;
    my $threatmap = $self->threat_map->{refaddr(TAEB->current_level)};
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
	return if $adjonly && $t > 0;
	$visitmap[$x]->[$y] = 1;
        my $txy = $threatmap->[$x]->[$y];
        # Monsters guarding stairs can attack us as we come back up.
        # Therefore, we give them two turn's advantage when
        # considering the threat on that square. The call to floor()
        # allows for monsters to get turns more often than expected
        # due to rounding errors.
	my $rt = floor(($t + $txy->{'stairsmod'}) / $relspeed);
	$txy->{"$rt $planname"} = $danger
            unless ($adjonly && exists $txy->{'boulder'})
                || (defined $nomark_tile &&
                    $x == $nomark_tile->x && $y == $nomark_tile->y);
	if ($movetype eq 'phase' || exists $txy->{$movetype}
                                 || $t == -1)
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
    # We also allow iteration over a TME chain. If $each returns true, then
    # the iteration stops; otherwise it continues. This can be undef.
    my $each  = shift;
    my $tme   = $self->tme_from_tile($tile);
    my $map   = $self->tactics_map;
    my $tct   = $self->tactical_target_tile // TAEB->current_tile;
    my $tsc   = $self->tactical_success_count;
    my $perform_sanity_checks = $self->sanity_checks;
    my @chain = ();
    # I don't care what Sartak says about return undef, I need to distinguish
    # failure from success with an empty list.
    return undef unless defined $tme;
    while(defined $tme && defined $tme->{'prevtile_level'}) {
	unshift @chain, $tme;
        return @chain if $each and $each->($tme);
        # If a tactic along the line is marked toxic, fail to generate a
        # chain (and do something else instead).
        return undef if $tme->{'tactic'}->toxic_until > $tsc;
	$tme=$self->tme_from_tile($tme->{'prevtile_level'}->
                                  at($tme->{'prevtile_x'},$tme->{'prevtile_y'}));
        if ($perform_sanity_checks) {
            refaddr $tme == refaddr $chain[$_] and
                die "TME (generated via " . $tme->{'source'} .
                ") refers to chain element $_ (" . $tme->{'tactic'}->name .
                " @ " . $tme->{'tile_x'} . ", " . $tme->{'tile_y'} . " (previous " .
                $tme->{'prevtile_x'} . ", " . $tme->{'prevtile_y'} . "), " .
                "aistep " . $tme->{'step'} . " which should be " .
                $self->aistep . ")"
                for 0..$#chain;
        }
    }
    if ($perform_sanity_checks) {
        if (defined $tme && (
                $tme->{'tile_x'} != $tct->x ||
                $tme->{'tile_y'} != $tct->y ||
                $tme->{'tile_level'} != $tct->level)) {
            die "TME chain (starting at (" . $tile->x . ", " . $tile->y
                . ") on aistep " . $chain[$#chain]->{'step'} . ") "
                . "ends with " . $tme->{'tactic'}->name . " on aistep "
                . $tme->{'step'} . " at (" . $tme->{'tile_x'} . ", "
                . $tme->{'tile_y'} . ", " . $tme->{'tile_level'} . ") but "
                . "should end at (" . $tct->x . ", " . $tct->y . ", "
                . $tct->level . ") on aistep " . $self->aistep;
        } elsif (!defined $tme) {
            die "TME chain with positive length ended in undef";
        }
    }
    return @chain;
}
sub tme_from_tile {
    my $self = shift;
    my $tile = shift;
    return undef unless defined $tile;
    my $map  = $self->tactics_map->{refaddr $tile->level};
    return undef unless defined $map; # it might be on an unpathed level
    my $tme  = $map->[$tile->x]->[$tile->y];

    # It doesn't matter whether this TME is tainted; if it was
    # computed this step, it'll be accurate anyway.
    return $tme if defined $tme && $tme->{'step'} == $self->aistep;

    # If the TME's out of date but on our level, it means we had a
    # routing failure ('world' or 'level' algorithms), or that we need
    # to look at the chokepoint maps ('chokepoint' algorithm).
    # Likewise, if the TME is undef.
    my $tct = $self->tactical_target_tile // TAEB->current_tile;
    if ($tile->level == $tct->level) {
        return undef unless $self->tactical_algorithm_this_turn eq 'chokepoint';
        # Get an updated interchokepoint TME. This works pretty much
        # the same way as an updated interlevel TME, except that we
        # need to find the chokepoints that we can possibly use to
        # reach this TME from. (If it's on the main map, even tainted,
        # it'll have been returned already; so we know we have to go
        # via a chokepoint.)
        my $cpset = $self->nearby_chokepoints->{$tile};
        # If we've never managed to route to the tile from anywhere, it's
        # obviously unroutable now.
        return undef unless $cpset;
        my $tpr = $self->resources;
        my $aistep = $self->aistep;
        my $bestcp = undef;
        my $bestrisk = '+inf';
        my $bestrisksp = undef;
        my $besttme = undef;
        my $clu = $self->chokepoint_last_updated;
        for my $chokepoint ($cpset->elements) {
            # Use only chokepoint maps which have been updated at some point.
            next unless $clu->{refaddr $chokepoint};
            my $cpmap = $self->fetch_tactics_map($chokepoint);
            my $cptme = $cpmap->{refaddr $tile->level}->[$tile->x]->[$tile->y];
            next unless defined $cptme;
            next if $cptme->{'taint'};
            # This is the only case in which nearby_chokepoints won't have been
            # updated already. We may as well do that now to speed up access on
            # future turns.
            $cpset->delete($chokepoint), next if $cptme->{'step'} <
                $clu->{refaddr $chokepoint};
            my $maintmeforcp = $map->[$chokepoint->x]->[$chokepoint->y];
            next unless defined $maintmeforcp;
            next if $maintmeforcp->{'step'} != $aistep;
            my %calc_risk = %{$cptme->{'risk'}};
            my $tmerisk = $maintmeforcp->{'risk'};
            $calc_risk{$_} += $tmerisk->{$_} for keys %$tmerisk;
            my $nrisk = 0;
            $nrisk += $tpr->{$_}->cost($calc_risk{$_}) for keys %calc_risk;
            if ($nrisk < $bestrisk) {
                $bestrisk = $nrisk;
                $bestrisksp = \%calc_risk;
                $bestcp = $chokepoint;
                $besttme = $cptme;
            }
        }
        # The square might be unroutable.
        return undef unless defined $bestcp;
        # Looks like it is routable; generate a TME for it.
        my %newtme = %$besttme;
        $newtme{'risk'} = $bestrisksp;
        $newtme{'source'} = 'interchokepoint';
        $newtme{'step'} = $self->aistep;
        bless \%newtme, "TAEB::AI::Planar::TacticsMapEntry";
        $map->[$tile->x]->[$tile->y] = \%newtme;
        return \%newtme;
    }
    return undef unless defined $tme; # we might not be able to route there

    # Get an updated interlevel TME. We recalculate the risk fields of
    # the TME in question by getting the TME from the previous level, then
    # adding the level-risk of this one. This is done recursively, so it
    # will work over all levels, even if the tactics map is being calculated
    # lazily.

    # This case can happen on a disconnected map.
    return undef unless $tme->{'prevlevel_level'};
    my $prevtme = $self->tme_from_tile(
        $tme->{'prevlevel_level'}->at(
            $tme->{'prevlevel_x'}, $tme->{'prevlevel_y'}));
    return undef unless $prevtme && $prevtme->{'step'} == $self->aistep;
    my %risk = %{$tme->{'level_risk'}};
    $risk{$_} += $prevtme->{'risk'}->{$_} for keys %{$prevtme->{'level_risk'}};
    $tme->{'risk'} = \%risk;
    $tme->{'step'} = $self->aistep;
    $tme->{'make_safer_plans'} = $prevtme->{'make_safer_plans'};
    $tme->{'source'} = 'interlevel';
    return $tme;
}

sub monster_is_peaceful {
    my $self = shift;
    my $monster = shift;
    my $disposition = $monster->disposition;
    defined $disposition or $monster->definitely('always_hostile')
        && return 0;
    defined $disposition or
         return !($monster->is_hostile() // 1);
    my $rv = $disposition eq 'peaceful'
          || $disposition eq 'tame';
    return $rv;
}

has (last_floor_check => (
    isa => 'Int',
    is => 'rw',
    default => -1,
    traits  => [qw/TAEB::AI::Planar::Meta::Trait::DontFreeze/],
));
sub msg_check {
    my $self = shift;
    my $what = shift;
    $self->last_floor_check(TAEB->step) if ($what//'') eq 'floor';
}

has (threat_count => (
    isa => 'Int',
    is => 'rw',
    default => 0,
    traits  => [qw/TAEB::AI::Planar::Meta::Trait::DontFreeze/],
));
sub threat_check {
    my $self = shift;
    # Clear the threat map for the current level.
    my $current_level = TAEB->current_level;
    my $threat_map = $self->threat_map;
    my $tmcl = $threat_map->{refaddr $current_level} = [];
    my $count = 0;
    # Mark squares on the threat map as impassable to monsters, if
    # necessary. Monster routing is much more primitive than player
    # routing, for efficiency reasons.
    for my $x (0..79) {
	my $col = $tmcl->[$x] = [];
	for my $y (1..21) {
	    my $tile = $current_level->at($x,$y);
	    my $type = $tile->type;
	    my $coly = $col->[$y] = {};
            if ($tile->has_boulder) {
                $coly->{'phase'} = undef;
                $coly->{'boulder'} = undef;
            }
 	    elsif ($type eq 'rock' || $type eq 'closeddoor' ||
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
                $coly->{'phase'} = undef;
                $coly->{'eignore'} = undef;
 	    }
            # Stairs, we have to come back to blind, so they give two
            # turns of advantage to the monster.
            $coly->{'stairsmod'} =
                $tile->isa("TAEB::World::Tile::Stairs") ? -2 : 0;
	}
    }
    # The current tile is impassible to monsters for the space of one
    # action if it has at least 3 intact Elbereths.
    # TODO: Other tiles with Elbereth on?
    # TODO: This is not true for attacks that would scuff an Elbereth
    # up (noticeably melee and projectiles).
    my $tct = TAEB->current_tile;
    # No point in checking if there was no Elbereth written here
    # beforehand and we weren't alerted when we stepped on the tile,
    # we won't have had one magically appearing. Also, no point in
    # checking more than once in a turn.
    my $default_ignore = undef;
    if ($self->last_floor_check < TAEB->step && $tct->elbereths) {
        TAEB->send_message(check => 'floor');
    }
    my $ecount = $tct->elbereths;
    if ($ecount >= 3 ||
        ($ecount >= 1 && $tct->engraving_type eq 'burned')) {
        $default_ignore = $tct;
    }

    # The most important threats in the game are monsters on the
    # current level.
    my @enemies = $current_level->monsters;
    my $selfspeed = TAEB->speed || 12; # invariant code motion
    for my $enemy (@enemies) {
	my $tile = $enemy->tile;
        $self->last_monster_seen_step(TAEB->step);
	# Work out what type of enemy this is. If we know its spoiler
	# from its Monster.pm data (i.e. unique glyph and colour),
	# then use that; otherwise, farlook at it and see if we have a
	# spoiler from that. Also, if not an always-hostile, farlook to
        # determine disposition; peacefuls can be angered.
	$enemy->definitely_known && $enemy->definitely('always_hostile')
            or $tile->glyph eq 'I' or TAEB->is_hallucinating or $enemy->farlook;
	my $spoiler = $enemy->spoiler;
	my $danger = {};
	my $relspeed = 0.99; # to encourage running away from unknown monsters
        my $disposition = $enemy->disposition // 'hostile';
        my $movetype = 'walk';
        my $nomarktile = $default_ignore;

        # Tame and peaceful monsters are not threats. We can't route
        # through peacefuls, though.
        next if $disposition eq 'tame';
        # Record that the monster can't be routed through.
	my $plan = $self->get_plan("Eliminate", $enemy);
	my $threatmap = $self->threat_map->{refaddr($current_level)};
        $threatmap->[$tile->x]->[$tile->y]->{"-1 ".$plan->name}
            = {Impossibility => 1};
        next if $disposition eq 'peaceful';

	if (defined($spoiler)) {
	    # Passive-attack-only monsters are not dangerous to walk past,
	    # and therefore not threats (they're risky to attack, but not
	    # threatty).
	    my $passive_only = 1;
            $passive_only &&= ($_->{mode} eq 'passive') for @{$spoiler->attacks};
	    next if $passive_only;
	    # Use the built-in TAEB maximum-damage function.
	    my $damagepotential = $enemy->maximum_melee_damage;
	    $danger = {'Hitpoints' => $damagepotential};
	    # We hates nymphs
	    my $attack;
	    if ($attack = $spoiler->has_attack('stealitem')) {
		for my $r (qw/AC DamagePotential Zorkmids/) {
		    $danger->{$r} = $self->resources->{$r}->amount / 10;
		}
	    }
	    # Yellow lights make us waste lots of time
	    if ($attack = $spoiler->has_attack('blind')) {
		$attack->{damage} =~ /(\d+)d(\d+)/;
		$danger->{'Time'} = $1 * ($2 + 1) / 2;
	    }
	    $relspeed = $$spoiler{speed} / $selfspeed;
            $nomarktile = undef if $spoiler->ignores_elbereth;
	} else { # use a stock value as we don't know...
	    $danger = {'Hitpoints' => 5};
	}
	$plan = $self->get_plan(
            ($movetype ne 'eignore' ? "Mitigate" : "MitigateWithoutElbereth"),
            $enemy);
	# TODO: walk/fly/swim
	$self->add_threat($plan->name,$danger,$tile,$relspeed,$movetype,
                          $nomarktile,
                          $enemy->is_unicorn || $enemy->glyph eq 'I');
        $count++;
#	TAEB->log->ai("Adding monster threat ".$plan->name." $danger ".
#            ($nomarktile // 'undef'));
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
	my $threatmap = $self->threat_map->{refaddr($current_level)};
	TAEB->current_tile->each_adjacent(sub {
	    my $tile = shift;
	    # The impossibility here is to force Extricate to run
            # strategically rather than tactically, if we want to
            # do any routing at all. (Things that can be done when
            # stationary, like eating food rations, or meleeing
            # from the current square, don't need extrication
            # first.)
	    $threatmap->[$tile->x]->[$tile->y]->{"-1 Extricate"}
	        = {Impossibility => 1};
            $count++;
	});
	$self->get_plan("Extricate")->validate();
    }
    # Similar to traps: engulfing monsters.
    if (TAEB->is_engulfed) {
	my $threatmap = $self->threat_map->{refaddr($current_level)};
	TAEB->current_tile->each_adjacent(sub {
	    my $tile = shift;
	    $threatmap->[$tile->x]->[$tile->y]->{"-1 Unengulf"}
	        = {Impossibility => 1};
            $count++;
	});
	$self->get_plan("Unengulf")->validate();
    }
    # Shop doorways can't be entered while holding a digging tool. We
    # block all squares adjacent to the doorway that are inside the
    # shop.
    if (TAEB::AI::Planar::Plan::Tunnel->has_pick &&
        !TAEB->current_tile->in_shop) {
        for my $door ($current_level->tiles_of("opendoor")) {
            if ($door->any_orthogonal(sub{shift->in_shop})) {
                my $threatmap = $self->threat_map->{refaddr($current_level)};
                $door->each_adjacent(sub {
                    my $tile = shift;
                    if ($tile->in_shop) {
                        $threatmap->[$tile->x]->[$tile->y]->
                        {"-1 ".$self->get_plan("EnterShop", $door)->name}
                        = {Impossibility => 1};
                    }
                });
                $count++;
            }
        }
    }
    $self->threat_count($count);
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

sub plans_by_type {
    my $self = shift;
    my $arg  = shift;

    return @{ $self->plan_index_by_type->{$arg} ||= weak_set() };
}

sub plans_by_obj {
    my $self = shift;
    my $arg  = shift;

    return @{ $self->plan_index_by_object->{$arg} ||= weak_set() };
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
	($pibo->{$1} ||= weak_set())->insert($plan);
    }
    {
        my $pibt = $self->plan_index_by_type;
	($pibt->{$name} ||= weak_set())->insert($plan);
    }
}

sub loadplans {
    my $self = shift;
    # Load plans.
    TAEB->log->ai("Loading plans...");

    # Require the module for each plan we could use.
    # The list here is of plans referenced by the core AI itself.
    my @planlist = (
	# Validity metaplans
	"InventoryItemMeta", # metaplan for inventory items
	"GroundItemMeta",    # metaplan for floor items
	"Investigate",       # metaplan for interesting tiles
	"MonsterMeta",       # metaplan for monsters
        "TerrainMeta",       # metaplan for unusual terrain
        "CharacterMeta",     # metaplan for intrinsics, etc
	# Threat metaplans
	"Mitigate",          # metaplan for monsters
	"MitigateWithoutElbereth",  # and for Elbereth-ignoring monsters
        "Eliminate",         # route past a monster
	"Extricate",         # metaplan for traps we're in
        "Unengulf",          # (meta)plan for engulfing monsters
        "Unlevitate",        # plan for removing levitation items
        "EnterShop",         # plan for getting past shop doorways
        "DefensiveElbereth", # a dependency of strategic plans in general
	# Tactical metaplans
	"MoveTo",            # tactical metaplan for normal movement
	"MoveFrom",          # tactical metaplan for unusual movement
	"Nop",               # stub tactical plan
	# Goal metaplans
	$self->overall_plan);# metaplan for strategy
    my %processed = ();

    # Load each plan, and recursively load its references.
    while (@planlist) {
	my $planname = shift @planlist;
	next if $processed{$planname};
	$processed{$planname} = 1;
	my $pkg = "TAEB::AI::Planar::Plan::$planname";
	TAEB->log->ai("Loading plan $planname");
        Class::MOP::load_class("$pkg");
	my @referencedplans = @{$pkg->new->references};
	@planlist = (@planlist, @referencedplans);
    }
}

#####################################################################
# Things below this line should be elsewhere or handled differently

has (tiles_on_path => (
    isa => 'HashRef[Int]', # !exists for not on path, 1 for on path, 2 for endpoint
    is  => 'rw',
    default => sub { {} },
    traits  => [qw/TAEB::AI::Planar::Meta::Trait::DontFreeze/],
));

sub drawing_modes {
    exploration_cache => {
        description => 'Show exploration cache',
        color => sub {
            my $tile = shift;
            my $ai = TAEB->ai;
            my $status = $ai->plan_caches->{'ExploreLevel'}->{refaddr $tile};
            my $c;
            $status //= 0;
            $status ==  0 and $c = display_ro(color => COLOR_GRAY,    reverse => 1);
            $status ==  1 and $c = display_ro(color => COLOR_YELLOW,  reverse => 1);
            $status ==  2 and $c = display_ro(color => COLOR_RED,     reverse => 1);
            $status ==  3 and $c = display_ro(color => COLOR_MAGENTA, reverse => 1);
            $status ==  4 and $c = display_ro(color => COLOR_YELLOW,  reverse => 1);
            $status ==  5 and $c = display_ro(color => COLOR_RED,     reverse => 1);
            $status == -1 and $c = display_ro(color => COLOR_GREEN,   reverse => 1);
            $status == -2 and $c = display_ro(color => COLOR_CYAN,    reverse => 1);
            $status == -3 and $c = display_ro(color => COLOR_BLUE,    reverse => 1);
            return $c;
        },
    },
    chokepoint => {
        description => 'Show chokepoint map',
        color => sub {
            my $tile = shift;
            my $ai = TAEB->ai;
            my $tcl = $tile->level;
            my $cpvalue = $ai->chokepoint_map->{refaddr $tile} // 0;
            my $c;
            $cpvalue ==  0 and $c = display_ro(color => COLOR_GRAY);
            $cpvalue ==  1 and $c = display_ro(color => COLOR_BLUE);
            $cpvalue ==  2 and $c = display_ro(color => COLOR_CYAN);
            $cpvalue ==  3 and $c = display_ro(color => COLOR_RED);
            $cpvalue == -2 and $c = display_ro(color => COLOR_YELLOW);
            return $c;
        },
    },
    tactical => { 
        description => 'Show tactical map',
        color => sub {
            my $tile = shift;
            my $ai = TAEB->ai;
            my $tme = $ai->tme_from_tile($tile);
            my $risk = defined $tme ? $tme->numerical_risk : undef;
            my $color = sub {
                defined $risk    or return (COLOR_GRAY);
                $risk <    0.51 and return (COLOR_BLUE);
                $risk <    1.01 and return (COLOR_CYAN);
                $risk <    2.01 and return (COLOR_GREEN);
                $risk <  100.01 and return (COLOR_BROWN);
                $risk < 5000.01 and return (COLOR_YELLOW);
                $risk <  200000 and return (COLOR_RED);
                return (COLOR_MAGENTA);
            }->();
            defined $ai->current_plan
                and $ai->current_plan->can('aim_tile_cache')
                and $tile == $ai->current_plan->aim_tile_cache
                and return display_ro(color => $color, reverse => 1);
            return display_ro($color);
        },
    },
    tactical_algorithms => {
        description => 'Show tactical algorithms',
        color => sub {
            my $tile = shift;
            my $ai = TAEB->ai;
            my $tme = $ai->tme_from_tile($tile);
            my $algo = $tme->{'source'} // '';
            $algo eq 'globalchokepoint'
                and return display_ro(color => COLOR_MAGENTA, reverse => 1);
            $algo eq 'interchokepoint'
                and return display_ro(color => COLOR_RED, reverse => 1);
            $algo eq 'interlevel'
                and return display_ro(color => COLOR_CYAN, reverse => 1);
            $algo eq 'world'
                and return display_ro(color => COLOR_BLUE, reverse => 1);
            $algo eq 'level' || $algo eq 'nop' and return display_ro(
                color => ($tme->{'taint'} ? COLOR_BROWN : COLOR_GREEN),
                reverse => 1);
            # unroutable
            return display_ro(color => COLOR_GRAY, reverse => 1);
        },
    },
    planar_debug => {
        description => 'Planar-enhanced debug colors',
        onframe => sub {
            my $ai = TAEB->ai;
            my %path = ();
            defined $ai->current_plan
                &&  $ai->current_plan->can('aim_tile_cache')
                or  $ai->tiles_on_path({}), return;
            my $endpoint = $ai->current_plan->aim_tile_cache;
            my @chain = $ai->calculate_tme_chain($endpoint);
            defined $_ and
                $path{refaddr $_->{'tile_level'}->at($_->{'tile_x'},$_->{'tile_y'})} = 1
                for @chain;
            $path{refaddr $endpoint} = 2;
            $ai->tiles_on_path(\%path);
        },
        color => sub {
            my $tile  = shift;
            my $ai    = TAEB->ai;
            my $level = $tile->level;
            my $sokoban = $level->known_branch && $level->branch eq 'sokoban';

            my $color;
            # short-circuit optimisation for unexplored tiles
            return display_ro(COLOR_GRAY) if $tile->type eq 'unexplored';
            my @reverse = ();
            @reverse = (reverse => 1) if $tile->type eq 'rock';
            if((blessed $tile) eq 'TAEB::World::Tile') {
                # Use a slightly different colour scheme for tiles
                # which have no special overrides of their own
                $color = $tile->is_interesting
                    ? display_ro(color => COLOR_RED, @reverse)
                    : $tile->in_shop
                    ? display_ro(color => COLOR_BRIGHT_GREEN, @reverse)
                    : $tile->in_temple
                    ? display_ro(color => COLOR_BRIGHT_CYAN, @reverse)
                    : $sokoban && TAEB::Spoilers::Sokoban->
                      probably_has_genuine_boulder($tile)
                    ? display_ro(color => COLOR_WHITE, @reverse)
                    : $sokoban && $tile->has_boulder
                    ? display_ro(color => COLOR_ORANGE, @reverse)
                    : $tile->searched >= 20
                    ? display_ro(color => COLOR_CYAN, @reverse)
                    : $tile->stepped_on
                    ? display_ro(color => COLOR_BROWN, @reverse)
                    : $tile->explored
                    ? display_ro(color => COLOR_GREEN, @reverse)
                    : display_ro(color => COLOR_GRAY, @reverse);
            } else { $color = $tile->debug_color; }

            $color = display_ro(color => COLOR_MAGENTA, @reverse)
                if $ai->tiles_on_path->{refaddr $tile};
            $color = display_ro(color => COLOR_BRIGHT_MAGENTA, @reverse)
                if ($ai->tiles_on_path->{refaddr $tile} // 0) == 2;

            return $color;
        },
    },
}

sub STORABLE_freeze {
    my $self = shift;
    my $cloning = shift;
    return if $cloning;
    my %values;
    my @attrs = $self->meta->get_all_attributes;
    push @attrs, $self->meta->get_all_class_attributes
        if $self->meta->can('get_all_class_attributes');
    for my $attr (@attrs) {
        next if $attr->does('TAEB::AI::Planar::Meta::Trait::DontFreeze');
        $values{$attr->name} = $attr->get_read_method_ref->($self);
    }
    return ('TAEB::AI::Planar persistency', \%values);
}

sub STORABLE_thaw {
    my $self = shift;
    my $cloning = shift;
    my $serialized = shift;
    my $values = shift;
    return if $cloning;
    die "This doesn't seem to be a frozen TAEB::AI::Planar"
        unless $serialized eq 'TAEB::AI::Planar persistency';
    my $newself = (blessed $self)->new(%$values);
    my @attrs = $newself->meta->get_all_attributes;
    push @attrs, $newself->meta->get_all_class_attributes
        if $newself->meta->can('get_all_class_attributes');
    for my $attr (@attrs) {
        next unless $attr->does('TAEB::AI::Planar::Meta::Trait::DontFreeze');
        my $default = $attr->default($newself);
        $attr->get_write_method_ref->($newself,$default);
    }
    # Ugh: at this point we have to overwrite the internal object of $self,
    # according to the API of Storable, which means breaking encapsulation.
    # Assume it's a blessed scalar, array, or hash.
    my $package = blessed $self // $self;
    if   (reftype $newself eq 'SCALAR') {$$self = $$newself;}
    elsif(reftype $newself eq 'ARRAY' ) {@$self = @$newself;}
    elsif(reftype $newself eq 'HASH'  ) {%$self = %$newself;}
    else {die "Unable to determine the internals of a TAEB::AI::Planar object";}
    bless $self, $package;
}

sub initialize {
    my $self = shift;
    $self->loadplans;
    $self->institute;
}

has (walkability_cache => (
    isa     => 'HashRef[Maybe[Bool]]',
    is      => 'rw',
    default => sub { {} },
    traits  => [qw/TAEB::AI::Planar::Meta::Trait::DontFreeze/],
));
# A cached version of is_walkable (actually !is_inherently_unwalkable,
# but marking boulders as unwalkable).
sub tile_walkable {
    my $self = shift;
    my $tile = shift;
    return 0 if $tile->has_boulder;
    return $self->tile_walkable_or_boulder($tile, shift);
}
sub tile_eventually_walkable {
    my $self = shift;
    my $tile = shift;
    return 1 if $tile->type eq 'closeddoor';
    return $self->tile_walkable_or_boulder($tile, shift);
}
sub tile_walkable_or_boulder {
    my $self = shift;
    my $tile = shift;
    my $addr = refaddr $tile;
    if (shift) {
        return 1 if !TAEB->senses->is_blind
                 && $tile->type eq 'unexplored';
    }
    my $cache = $self->walkability_cache;
    return $cache->{$addr} if defined $cache->{$addr};
    return ($cache->{$addr} = (!$tile->is_inherently_unwalkable(0, 1)));
}

# Responding to messages.
has (try_again_step => (
    isa => 'Int',
    is  => 'rw',
    default => -1,
    traits  => [qw/TAEB::AI::Planar::Meta::Trait::DontFreeze/],
));
subscribe door => sub {
    my $self = shift;
    my $what = shift;
    if($what->state eq 'resists') {
	# The door actions can safely try again.
	$self->try_again_step(TAEB->step);
    }
};

has (problematic_levitation_step => (
    isa => 'Int',
    is  => 'rw',
    default => -1,
    traits  => [qw/TAEB::AI::Planar::Meta::Trait::DontFreeze/],
));
sub exception_impeded_by_levitation {
    my $self = shift;
    $self->problematic_levitation_step(TAEB->step);
    return;
}
subscribe impeded_by_levitation => sub {
    my $self = shift;
    $self->problematic_levitation_step(TAEB->step);
    return;
};

sub handle_tile_changes {
    # This might have made plans with the tile in question as an
    # argument possible, when they weren't before. We look through
    # the plan index by object to find them.
    my $self = shift;
    my $what = shift;
    my $tile = $what->tile;
    my $addr = refaddr($tile);
    defined $_ and $_->required_success_count(0)
	for $self->plans_by_obj($addr);
    # Also, invalidate the walkability cache for that tile.
    $self->walkability_cache->{$addr} = undef;
    $self->chokepoint_examine_tiles->insert($tile);
}

subscribe tile_type_change => \&handle_tile_changes;
subscribe boulder_change   => \&handle_tile_changes;


sub safe_to_travel {
    my $self = shift;
    return 0 if $self->veto_travel;
    return 0 if TAEB->current_level->has_monsters;
    return 0 if $self->last_monster_seen_step + 3 > TAEB->step;
    return 0 if TAEB->is_blind;
    return 0 if TAEB->current_level->known_branch
             && TAEB->current_level->branch eq 'sokoban'
             && TAEB::Spoilers::Sokoban->remaining_pits > 0;
    return 1;
}

has (item_subtype_cache => (
    isa     => 'HashRef[Str]',
    is      => 'rw',
    default => sub { {} },
    traits  => [qw/TAEB::AI::Planar::Meta::Trait::DontFreeze/],
));
# NetHack::Item is just far too slow at this...
# Luckily, subtypes don't change, so they can be cached.
# Before doing this, about 16% of Planar's time was spent in
# NetHack::Item calculating item subtypes.
# Note that we mustn't allow NHI to stringise the hash keys
# itself, or it ends up calculating the subtype in the process...
sub item_subtype {
    my $self = shift;
    my $item = shift;
    my $cache = $self->item_subtype_cache;
    return $cache->{refaddr $item} if exists $cache->{refaddr $item};
    my $subtype = undef;
    if ($item->can('subtype')) {
        $subtype = $item->subtype;
    }
    $cache->{refaddr $item} = $subtype;
    return $subtype;
}

# XXX XXX XXX We really ought to be using scarce value here, but the issues
# involved in comparing that really mess things up.
my $_best_valid_on_step = -1;
my $_best_shield_val;
my $_best_1hw_val;
my $_best_2hw_val;

sub _get_bests {
    my $self = shift;

    $_best_valid_on_step = $self->aistep;
    $_best_shield_val = 0;
    $_best_1hw_val = 0;
    $_best_2hw_val = 0;

    my $fdcalc = $self->resources->{'FightDamage'};

    # NOTE: Normally, FightDamage is treated as an ephemeral resource.
    # But here we're putting it against AC.
    my $val_fd = $fdcalc->value * $self->analysis_window;
    my $val_dpot = $self->resources->{'DamagePotential'}->value;
    my $val_ac = $self->resources->{'AC'}->value;

    my $base_sdam = $fdcalc->spell_damage(TAEB->power, shield => undef);

    for my $check (TAEB->inventory->items,
                   map {$_->items} (map {@$_} (@{TAEB->dungeon->levels}))) {
        if ($check->can('hands')) {
            my $hands = $check->hands;
            if (defined ($hands)) {
                if ($hands == 2) {
                    $_best_2hw_val = max(
                        $_best_2hw_val,
                        $val_dpot * TAEB::Spoilers::Combat->damage($check));
                } else {
                    $_best_1hw_val = max(
                        $_best_1hw_val,
                        $val_dpot * TAEB::Spoilers::Combat->damage($check));
                }
            }
        }

        if ($check->can('ac') && $self->item_subtype($check) eq 'shield') {
            my $val = $val_ac * $check->ac;
            $val -= $val_fd * ($base_sdam -
                $fdcalc->spell_damage(TAEB->power, shield => $check));

            $_best_shield_val = max($_best_shield_val, $val);
        }
    }
}

# A cache for use_benefit. What's cached is the value, and the step that
# the value is valid on; the key is "cost" or "anticost" followed by the
# item's refaddr.
has (_use_benefit_cache => (
    isa     => 'HashRef[ArrayRef[Num]]',
    is      => 'rw',
    default => sub { {} },
    traits  => [qw/TAEB::AI::Planar::Meta::Trait::DontFreeze/],
));

# The benefit that would be gained from wielding/wearing this; or the
# benefit that is gained from wielding/wearing this, in the case that
# it's already wielded/worn.
#
# Often, we don't know if an item will help.  Since we can always just
# take items off, the benefit is always at least 0.  So, we just assume
# that the item is better, and then downscale the benefit by the chance
# of this actually being the case.
sub use_benefit {
    my $self = shift;
    my $item = shift;
    my $cost = shift // 'anticost';
    my $aistep = $self->aistep;

    my $cel = $self->_use_benefit_cache->{$cost . refaddr $item};

    defined $cel and $cel->[1] == $aistep and return $cel->[0];

    my $anticost = ($cost eq 'cost' ? 'anticost' : 'cost');
    my $resources = $self->resources;
    my $value = 0;
    my $chance = 1;
    # Armour counts as its AC, plus any special abilities it
    # grants. Because we don't wear cursed armour, if it's unBCUed, we
    # multiply by .8682 (the chance of random armour not being cursed);
    # in addition, we subtract the AC of our current armour in the same
    # slot, unless the item is our current armour.
    if($item->can('ac') &&
       $self->item_subtype($item) && !$item->is_cursed) {{
        my $slot = $self->item_subtype($item);
        last unless TAEB->inventory->equipment->can($slot);
        my $ac = $item->ac;
        last unless defined $ac;
        my $currently_in_slot = TAEB->inventory->equipment->$slot;
        defined $currently_in_slot && $currently_in_slot->can('ac') &&
            defined $currently_in_slot->ac && $currently_in_slot != $item
            and $ac -= $currently_in_slot->ac;

        if (!defined ($item->is_cursed)) {
            $chance *= 0.8682;
        }

        # Putting on a shield costs us the difference between the best 2H
        # weapon and the best 1Her.
        if ($slot eq 'shield' && !defined($currently_in_slot)
                && $_best_1hw_val < $_best_2hw_val) {
            $value -= ($_best_2hw_val - $_best_1hw_val);
        }

        if (TAEB->spells->has_spells) {
            my $fd = $resources->{'FightDamage'};

            $value -= $fd->$anticost($fd->spell_damage(TAEB->power) -
                $fd->spell_damage(TAEB->power, $slot => $item)) *
                $self->analysis_window;
        }

        if (!$item->enchantment_known) {
            # This item is possibly not worth using.  But it might be!
            # Assume it has enough enchantment to make up the difference.
            #
            # Enchantment formula is 10% chance of rne(3); correlated with
            # beatitude, but we don't model that XXX

            if ($ac >= 0) {
                # Definitely worth trying, the possibility of an enchantment
                # only makes it moreso
                $ac += 0.15;
            } else {
                # We're gambling on the item being enchanted at all
                $chance *= 0.1;
                $ac += 1;

                # Further points are a bit more common
                while ($ac <= 0) { $ac++; $chance /= 3; }
            }
        }

        $value += $resources->{'AC'}->$cost($ac) unless $ac <= 0;
    }}
    # Likewise for weapons; for those we count their average damage. 90%
    # chance that they aren't cursed. We don't treat pickaxes as weapons
    # because it causes trouble in shops.
    if($item->isa("NetHack::Item::Weapon") && !$item->is_cursed
        && $item->appearance !~ /bolt|arrow|pick-axe|mattock/o) {
        my $current_weapon = TAEB->inventory->equipment->weapon;
        my $damage = TAEB::Spoilers::Combat->damage($item);
        $damage *= .9 unless defined $item->is_cursed; # i.e. we know it isn't
        defined $current_weapon && $current_weapon != $item and
            $damage -= TAEB::Spoilers::Combat->damage($current_weapon);

        my $ih = $item->hands;
        my $ch = $current_weapon ? $current_weapon->hands : 0;

        if ($ih == 2 && $ch != 2
            && $_best_shield_val > 0) {
            $value -= $_best_shield_val;
        }

        if ($ih == 1 && $ch != 1
            && $_best_shield_val > 0) {
            $value += $_best_shield_val;
        }

        $value += $resources->{'DamagePotential'}->$cost($damage)
            unless $damage <= 0;
    }

    $value *= $chance;

    $_ == $item and $value += $resources->{'Delta'}->$cost(1)
        for TAEB->inventory->items;

    $value -= $resources->{'Delta'}->$cost(1/refaddr($item)); # tiebreak

    $value = 0 if $value < 0;

    $self->_use_benefit_cache->{$cost . refaddr $item} =
        [$value, $aistep];

    return $value;
}

has (_devnull_item_hack => (
    isa     => 'Bool',
    is      => 'rw',
    default => sub {
	my $x = TAEB->config->get_ai_config->{'devnull_item_hack'} // 0;
	TAEB->log->ai("Initializing _devnull_item_hack to $x");
	$x;
    },
    traits  => [qw/TAEB::AI::Planar::Meta::Trait::DontFreeze/],
));

# Positive aspects of the item value.
sub item_value {
    my $self = shift;
    my $item = shift;
    my $resources = $self->resources;
    my $cost = shift // 'anticost';
    my $value = 0;

    if ($_best_valid_on_step != $self->aistep) {
        $self->_get_bests;
    }

    # If the item is permafood, its value is its nutrition minus its
    # weight; its nutrition is measured in unscarce units (twice the
    # base value for permafood), but its weight is measured in dynamic
    # units. (That allows us to drop things when we get burdened.)
    if($item->isa('NetHack::Item::Food')
    &&!$item->isa('NetHack::Item::Food::Corpse')
    && $item->name !~ /\begg\b/o
    && $item->is_safely_edible) {{
	last unless $item->nutrition;
	return $resources->{'Nutrition'}->base_value * 2 *
	    $item->nutrition * $item->quantity;
    }}
    # Gold has value measured in zorkmids.
    $item->identity and $item->identity eq 'gold piece' and
	$value += $resources->{'Zorkmids'}->$cost($item->quantity);
    $item->identity and $item->identity =~ /\b(?:spear|dagger|dart|rock|shuriken)\b/ and
        $value += $resources->{'FightDamage'}->$cost($item->quantity *
            TAEB::Spoilers::Combat->damage($item));
    # Pick axes help us dig.
    $item->match(identity => ['pick-axe', 'dwarvish mattock']) and
        $value += $resources->{'Tunnelling'}->$cost($item->quantity * 1e8);
    # Luckstones give us luck, but only if we don't already have one.
    if ($item->identity && $item->identity eq 'luckstone') {
	my $count = @{[ TAEB->has_item('luckstone') ]};

	if ($count == 0 || ($count == 1 && $cost eq 'cost')) {
	    $value += $resources->{'Luck'}->$cost(3);
	}
    }
    # Certain items are scored by ad-hoc patches in /dev/null
    if ($self->_devnull_item_hack
	    && (($item->appearance && ($item->appearance eq 'gray stone'
			|| $item->appearance eq 'bag'))
		|| $item->type eq 'amulet'))
    {
	$value += 1000;
    }
    # Things that we could use are useful as a result. However, we
    # don't want too many items that are redundant to each other. The
    # item we're currently wielding/wearing counts its full
    # use-benefit, as does the best other item (in inventory or on the
    # floor anywhere); but other items are penalised 90% of their benefit
    # for each nonwielded item better than them. If we have several such
    # items in inventory, we compare inventory letter as a tiebreak.
    my $use_benefit_factor = 1;
    my $benefit = $self->use_benefit($item,$cost);
    my $subtype = $self->item_subtype($item);
    $subtype = 'weapon' if $item->type eq 'weapon';
    if ($subtype) {
        C: for my $check (TAEB->inventory->items,
                          map {$_->items} (map {@$_} (@{TAEB->dungeon->levels}))) {
            $check->is_wielded || ($check->can('is_worn') && $check->is_worn)
                and next;
            $subtype eq 'weapon' and $check->type ne 'weapon' and next;
            if($subtype ne 'weapon') {
                my $check_subtype = $self->item_subtype($check);
                $check_subtype && $check_subtype eq $subtype or next C;
            }
            ($self->use_benefit($check,$cost) <=> $benefit
             || ($check->slot // ' ') cmp ($item->slot // ' ')) > 0
             and $use_benefit_factor /= 10;
        }
    }
    $item->is_wielded || ($item->can('is_worn') && $item->is_worn)
        and $use_benefit_factor = 1;
    $value += $benefit * $use_benefit_factor;
    return $value;
}
# Negative aspects of this item's value.
# This returns a spending plan, not a number like item_value does.
sub item_drawbacks {
    my $self = shift;
    my $item = shift;
    my $plan = {};
    # Weight.
    defined $item->weight and $plan->{'CarryCapacity'} += $item->weight;
    # TODO: Items with unknown weight should be marked as the maximum
    # possible weight for their type.
    # Cost.
    $item->cost and $plan->{'Zorkmids'} += $item->cost;
    return $plan;
}
# Item drawbacks, numerically at current values.
# Returns undef if we can't afford the item (either because it's in a
# shop and literally too expensive, or if it's dangerous to possess it
# for other reasons ("oY, loadstone...) In array context, returns
# a boolean saying if we can afford the item, followed by the numeric
# drawback.
# This uses cost if the item is not in the inventory, and value if it
# is, to prevent oscillations. XXX is this still needed
sub item_drawback_cost {
    my $self = shift;
    my $item = shift;
    my $costm = shift // 'cost';
    my $plan = $self->item_drawbacks($item);
    my $resources = $self->resources;
    my $cost = 0;
    my $canafford = 1;
    for my $resourcename (keys %$plan) {
	my $resource = $resources->{$resourcename};
	my $quantity = $plan->{$resourcename};
        if($item->slot && TAEB->inventory->get($item->slot)
                       && TAEB->inventory->get($item->slot) == $item) {
            $cost += $resource->value * $quantity;
            # Does this item break resource constraints?
            $resource->amount < 0 and $canafford = 0;
        } else {
            $cost += $resource->$costm($quantity);
            $quantity > $resource->amount and $canafford = 0;
        }
    }
    return ($canafford, $cost) if wantarray;
    return $cost if $canafford;
    return undef;
}

# If we're oscillating between pickup and drop, pick items up one at a
# time. This measures in main loop steps, not aisteps. Additionally,
# allow an extra step for #chat for price.
has (last_pickup_step => (
    isa     => 'Int',
    is      => 'rw',
    default => -1,
));
has (last_drop_step => (
    isa     => 'Int',
    is      => 'rw',
    default => -1,
));
sub pickup {
    my $self = shift;
    my $item = shift;
    # Pickup announcements would make this work better.
    my $value = $self->item_value($item);
    my $drawbacks = $self->item_drawback_cost($item);
    return 0 unless defined $drawbacks;
    # Pick up only 1 item if we dropped last turn.
    TAEB->log->ai("Not picking up a second item this step..."),
        $self->last_drop_step(TAEB->step), return 0
        if $self->last_drop_step >= TAEB->step-2
        && $self->last_pickup_step == TAEB->step;
    TAEB->log->ai("Not picking up $item (value $value, drawbacks $drawbacks)"), return 0
        if $value <= $drawbacks;
    $self->last_pickup_step(TAEB->step);
    TAEB->log->ai("Picking up $item (value $value, drawbacks $drawbacks)");
    return 1;
}
sub drop {
    my $self = shift;
    my $item = shift;
    my $value = $self->item_value($item, 'cost');
    my $drawbacks = $self->item_drawback_cost($item, 'anticost');
    $self->last_drop_step(TAEB->step);
    return 0 if !$item->can_drop;
    # If we're dropping things on an altar, may as well BCU while we're at it
    TAEB->current_tile->type eq 'altar'
        and !$item->is_blessed && !$item->is_uncursed && !$item->is_cursed
        and $item->identity ne 'gold piece'
        and !TAEB->is_blind && !TAEB->is_levitating
        and TAEB->log->ai("Dropping $item to BCU it"), return 1;
    TAEB->log->ai("Dropping $item as it has infinite drawbacks"), return 1
        unless defined $drawbacks;
    TAEB->log->ai("Dropping $item (value $value, drawbacks $drawbacks)"), return 1
        if $value < $drawbacks;
    TAEB->log->ai("Not dropping $item (value $value, drawbacks $drawbacks)");
    return 0;
}

__PACKAGE__->meta->make_immutable;
no Moose;

1;
