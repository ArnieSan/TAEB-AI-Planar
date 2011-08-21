#!/usr/bin/env perl
package TAEB::AI::Planar::Plan;
use TAEB::OO;
use Moose;

use overload (
    fallback => undef,
    q{==} => sub {shift->name eq shift->name;},
    q{!=} => sub {shift->name ne shift->name;},
);

use constant   difficulty_fading     => 3;
use constant d_difficulty_fading     => 1;
use constant d_difficulty_increase   => 9;
use constant d_difficulty_multiplier => 3;

# The difficulty that carrying out this plan has, and the amount its
# difficulty will increase by if something goes wrong. If a plan
# fails, its difficulty increases by d_difficulty, and d_difficulty
# increases by a factor of d_difficulty_multiplier and an amount of
# d_difficulty_increase; every time a plan is carried out, each other
# plan's difficulty decreases by difficulty_fading and its
# d_difficulty decreases by d_difficulty_fading. A plan will not be
# tried if it has positive difficulty; this stops oscillations pretty
# much outright, as the d_difficulty level increases over time while
# an oscillation occurs. When a plan fails, it can add an amount of
# desire for each plan that would help it succeed, up to the amount of
# desire it itself has (each plan can gain as much desire as it has,
# although it might choose to split or duplicate instead); this is the
# main AI structure of the game, meaning that the subplans needed to
# carry out the major plans take place. If a plan has positive
# difficulty it always fails (to prevent it being tried), but it can
# still confer desire onto other plans.

# The difficulty is calculated dynamically from the AI success count
# and this value, which is the success count required before it
# considers trying again.
has (required_success_count => (
    isa => 'Int',
    is  => 'rw',
    default => 0,
));
has (d_difficulty => (
    isa => 'Int',
    is  => 'rw',
    default => 0,
));
has (last_marked_impossible => (
    isa => 'Int',
    is  => 'rw',
    default => 0,
));
sub appropriate_success_count {
    return TAEB->ai->strategic_success_count;
}
sub difficulty {
    my $self = shift;
    my $difficulty = $self->required_success_count -
	$self->appropriate_success_count;
    return 0 if $difficulty <= 0;
    return $difficulty;
}

# Most plans are abandoned by marking them impossible, without
# increasing d_difficulty above 5.
sub abandon {
    my $self = shift;
    $self->mark_impossible(5);
}

# How to mark a plan as impossible. This has to retroactively figure
# out how much d_difficulty faded since it was last marked impossible
# (to prevent the need to update d_difficulty everywhere every step).
sub mark_impossible {
    return if TAEB->config->get_ai_config->{'stubborn'};

    my $self = shift;
    my $max_new_d_difficulty = shift // 1000;
    my $asc = $self->appropriate_success_count;
    my $elapsed = $asc - $self->last_marked_impossible;
    my $d_difficulty = $self->d_difficulty;
    $max_new_d_difficulty = $d_difficulty
        if $d_difficulty > $max_new_d_difficulty;
    $d_difficulty -= $elapsed * d_difficulty_fading;
    $d_difficulty < d_difficulty_increase
	and $d_difficulty = d_difficulty_increase;
    $self->required_success_count($asc + $d_difficulty);
    $d_difficulty += d_difficulty_increase;
    $d_difficulty *= d_difficulty_multiplier;
    $d_difficulty = $max_new_d_difficulty
        if $d_difficulty > $max_new_d_difficulty;
    $self->d_difficulty($d_difficulty);
    $self->last_marked_impossible($asc);
    #D#TAEB->log->ai("Marking " . $self->name .
    #D#	" impossible/abandoned with max $max_new_d_difficulty");
    #D#TAEB->log->ai("New difficulty " . ($self->required_success_count - $asc));
    #D#TAEB->log->ai("New d_difficulty $d_difficulty");
}

# The risk of carrying out this plan, undef if it hasn't been
# calculated yet. To save time, this is calculated lazily at every
# step, and only if we're considering carrying out the plan
# anyway. (You may recognise this as a version of A*, where the search
# space is that of plans.) It's set to undef if it hasn't been
# calculated yet, and to the risk value if it has. Risk is a
# combination of expense (the amount of resources which will need to
# be spent to carry out the plan in addition to any which are
# intrinsically part of it, for instance the number of turns needed to
# walk to a shop (not an intrinsic part of the plan) to exchange money
# for an item (which is an intrinsic part of the plan), and danger
# (the chance that we'll incur threats on the way). To save
# calculation time, threats which obviously exist /now/ are already
# pre-calculated before any risk calculation is done, although they
# add to the risk of everything; plans can spread desirability to
# things which would reduce the risk incurred by calculating
# them. Risk reduces desirability, but is not a plan failure; instead,
# it defers the plan and it is considered again later.
has (risk => (
    isa => 'Maybe[Num]',
    is  => 'rw',
    default => undef,
));
# To avoid having to loop over plans invalidating risk. This also
# controls spending plan validity.
has (risk_valid_on_step => (
    isa => 'Int',
    is  => 'rw',
    default => -1,
));

# This plan was called by the make_safer mechanism, and as such does
# not suffer the "letting threat stand" longsightedness penalties.
has (in_make_safer_on_step => (
    isa     => 'Int',
    is      => 'rw',
    default => -1,
));

# Calculate the risk of carrying out this plan, and spread
# desirability to other plans which reduce its risk. (Typically, such
# spreading would increase the desirability of the risk-reducing plans
# to equal the desirability of the current plan, rather than adding an
# amount; therefore, reducing the risk of a plan would be carried out
# iff the plan itself would be.) The default is only suitable for an
# always-failing plan, and marks the risk as 0, so the plan will be
# tried (and therefore bumped) instantly. Note that for a tactical
# plan, this will get the plan's TME for this turn as an argument.
sub calculate_risk {
    return 0;
}

# The spending plan for this plan; how much of what would need to be
# spent to make it work.
has (spending_plan => (
    isa => 'HashRef',
    is  => 'rw',
    default => sub { {} },
));

# A function that calculate_risk's likely to call a lot; this returns
# the cost for the given amount of the appropriate resource, and also
# places it on the spending plan which try uses to adjust the value of
# resources. (We also have a plan failure in try if the plan would
# spend resources that we don't have.) This can be used both for
# actual costs ("It'll cost me $60 to buy that nice shiny food
# ration") and potential costs ("If I run down to dlevl 10 without
# leveling up, I'll probably take about 100 points of damage"). A plan
# that potentially incurs more of a resource than we have will
# plan-fail; in theory this ought to prevent us doing anything
# dangerous. The practice is ofc likely to end up different...
sub cost {
    my $self = shift;
    my $resourcename = shift;
    my $amount = shift;
    if (exists $self->spending_plan->{$resourcename}) {
	$self->spending_plan->{$resourcename} += $amount;
    } else {
	$self->spending_plan->{$resourcename} = $amount;
    }
    # If called in void context, don't bother to figure out what the
    # cost is or the resource name validity yet; that can be left for
    # later when the plan is enacted. Just bill the item for later use
    # and return.
    defined(wantarray) or return;
    my $resources = TAEB->ai->resources;
    die "Resource $resourcename isn't a resource" unless
	exists $resources->{$resourcename};
    return $resources->{$resourcename}->cost($amount);
}
# Alternatively, we can get the cost from a TME, common if we're
# pathing somewhere.
sub cost_from_tme {
    my $self = shift;
    my $tme  = shift;
    my $risk = $tme->{'risk'};
    my $cost = 0;
    $cost += $self->cost($_,$$risk{$_}) for keys %$risk;
    return $cost;
}

# The danger of staying on this level for one turn (in terms of
# monster attacks, or similar). This invokes cost(), and therefore
# adds it to our spending plan.
sub level_step_danger {
    my $self = shift;
    # TODO: A value that isn't just a wild guess
    return $self->cost("Hitpoints", 0.01);
}

# Set up for an iteration of plan calculation.
sub next_plan_calculation {
    my $self = shift;
    $self->risk(undef);
    $self->spending_plan({});
}

# Plans can generate desire on their own right, if they would give us
# a net gain in resources. This is purely to do with
# resource-conversion plans; other plans should leave this at its
# default of doing nothing, and put any resource cost that may become
# relevant in calculate_risk instead. The desire is gained via
# add_capped_desire on the AI itself.
sub gain_resource_conversion_desire { }

# The name of this plan. This is used to determine whether two plans
# are the same or different. In some cases, a plan will take
# arguments; for instance, for each item we have a plan for each
# possible use for it. In this case, the name reflects both the use
# and the item for which it is responsible; instances of a plan,
# therefore, may have longer names than the plan itself.
# A plan in package TAEB::AI::Planar::Plan::Foo is named Foo; if it refers
# to an object $object, it's called Foo[refaddr($object)]. (Here
# $object could be a monster, item, or whatever.)
# The name is set automatically by the AI itself, rather than by the
# package, according to the package's filename and argument.
has (name => (
    isa => 'Str',
    is  => 'rw',
));
sub shortname {
    my $self = shift;
    local $_ = $self->name;
    /^(\w+)/;
    return $1;
}

sub set_arg {
    die "Tried to set an argument of a plan that doesn't take one";
}

# The description of this plan; used to tell people what we're doing.
has (description => (
    isa => 'Str',
    is  => 'rw',
));

# Can we afford to carry out this plan?
sub affordable {
    my $self = shift;
    my $cando = 1;
    for my $resourcename (keys %{$self->spending_plan}) {
        my $resource = TAEB->ai->resources->{$resourcename};
        my $spendamount = $self->spending_plan->{$resourcename};
        # TODO: want_to_spend is a no-op anyway atm, but if it ever gets
        # implemented this call will need to be conditionalised.
        $resource->want_to_spend($spendamount);
        $resource->amount < $spendamount and
            $cando = 0, TAEB->log->ai(
                $self->name . " failed because $resourcename was needed (" .
                $resource->amount . " < " . $spendamount . ")");
    }
    return $cando;
}

# Trying this plan. If the attempt fails, mark the plan as impossible.
# Some plans are too generic to correspond to any action, so always
# fail, which is the default. This does not spread desirability,
# that's done by spread_desirability, which is called by the AI when
# the plan fails.
sub try {
    my $self = shift;
    my $action = $self->action;
    my $cando = 1;
    return undef unless defined $action;
    # We plan-fail now if we can't afford to carry out this plan.
    if (defined $action) {
        $cando = $self->affordable;
    }
    $cando and return $action;
    return undef;
}

# The default implementation of try calls this function to determine
# the action to take, considering it a plan failure if this returns
# undef (the default).
sub action {
    undef;
}

# How far are we through with this plan? It could have succeeded, or
# failed, or still be ongoing; return 1, 0, and undef for these three
# possibilities. It's called when the tactic succeeds, or if there
# wasn't a tactic; if there was, the tactic is given as an argument.
sub succeeded {
    0;
}

# Plans to remove difficulty from when this plan succeeds. It's a hash
# from plan names to the plans.
has (reverse_dependencies => (
    isa => 'HashRef[TAEB::AI::Planar::Plan]',
    is  => 'rw',
    default => sub { {} },
));
# Reset difficulty but not d_difficulty. That way, there's still a
# timeout if this didn't make the plan possible after all.
sub reactivate_dependencies {
    my $self = shift;
    my @deps = values %{$self->reverse_dependencies};
#    TAEB->log->ai($self->name . " was reactivated.");
    $self->reverse_dependencies({});
    $_->required_success_count(-1), $_->reactivate_dependencies for @deps;
}

sub was_caused_by {
    my $self = shift;
    my $plan = shift;
    my $seen = shift // {};
    return 1 if $plan == $self; # plans cause themselves
    # and a plan is caused by a cause if something caused by that
    # cause depends on the plan
    return if $seen->{$self->name}; # avoid a causality loop
    $seen->{$self->name} = 1;
    $_->was_caused_by($plan,$seen) and return 1
        for values %{$self->reverse_dependencies};
    return;
}

# What the AI told us our desire was, so we can spread it properly.
has (desire => (
    isa => 'Num',
    is  => 'rw',
));
has (desire_with_risk => (
    isa => 'Num',
    is  => 'rw',
));

# The path used to give desirability to this plan
has (dependency_path => (
    isa     => 'ArrayRef[TAEB::AI::Planar::Plan]',
    is      => 'rw',
    default => sub { [] },
));
has (dependency_path_aistep => (
    isa     => 'Num',
    is      => 'rw',
    default => -1,
));
sub add_dependency_path {
    my $self = shift;
    my $on = shift;
    my $aistep = TAEB->ai->aistep;
    my $newdeppath = [@{$self->dependency_path},$self];
    $on->dependency_path($newdeppath)
        if scalar @$newdeppath <= scalar $on->dependency_path
        || $on->dependency_path_aistep != $aistep;
    $on->dependency_path_aistep($aistep);
}

# This plan depends on another plan. Normally, this will be called in
# spread_desirability. This increases the desirability of the other
# plan to this plan's desirability plus the log of a constant, and
# adds this plan as a dependency to the other plan.
sub depends {
    my $self = shift;
    my $ratio = shift;
    my $ai = TAEB->ai;
    my $aistep = $ai->aistep;
    my $on = $ai->get_plan(@_);
    $on->in_make_safer_on_step($aistep)
	if $self->in_make_safer_on_step == $aistep;
    $on->reverse_dependencies->{$self} = $self;
    $ai->add_capped_desire($on, $self->desire + 1e6 * log $ratio);
    $self->add_dependency_path($on);
}
# The same as above, but taking the amount of risk into account.
sub depends_risky {
    my $self = shift;
    my $ratio = shift;
    my $ai = TAEB->ai;
    my $on = $ai->get_plan(@_);
    $on->in_make_safer_on_step(TAEB->ai->aistep)
	if $self->in_make_safer_on_step == TAEB->ai->aistep;
    $on->reverse_dependencies->{$self} = $self;
    $ai->add_capped_desire($on, $self->desire_with_risk + 1e6 * log $ratio);
    $self->add_dependency_path($on);
}

# Spread the desirability of this plan onto other plans which might
# make it possible (as opposed to other plans which might make it less
# risky). The default spreads no desirability due to not knowing /why/
# the plan failed. This will normally be done by means of calling
# depends (which is used for both absolute dependencies, and a "this
# plan helps" sort of dependency).
sub spread_desirability {
}

# The validity of a plan is used to determine whether it still makes
# sense. (Merely being impossible to fulfil does not prevent a plan
# making sense; it's things like attacking a monster which no longer
# exists that do.) Many plans are always valid, which is why
# invalidate does nothing by default; plans which should
# auto-invalidate should declare invalidate to set validity to 0,
# and plans can also self-invalidate by setting validity to 0
# elsewhere (succeeded is common, as plans normally act to make
# themselves redundant due to their nature).
has (validity => (
    isa => 'Bool',
    is  => 'rw',
    default => 1
));
sub validate {
    my $self = shift;
    $self->validity or TAEB->ai->validitychanged(1);
    $self->validity(1);
}
sub invalidate { }

# Metaplans do nothing but spawn other plans.
# Even non-metaplans may want to spawn sometimes.
sub planspawn { }

has (last_planspawn => (
    isa => 'Int',
    is  => 'rw',
    default => -1
));
sub maybe_planspawn {
    my $self = shift;
    my $aistep = shift;
    if ($self->last_planspawn != $aistep) {
        $self->planspawn;
        $self->last_planspawn($aistep);
    }
}

# Plans which this plan can refer to (by spawning, depending, or
# otherwise generating).
sub references { [] }

# Plans which mustn't be used to interrupt this plan
sub uninterruptible_by { [] }
# Plans which mustn't be used immediately after this plan succeeds
sub unfollowable_by { [] }

# Stuff to remove once a better way is available
sub item_tile {
    my $self = shift;
    my $item = shift;
    return TAEB->current_level->first_tile(sub {
	$_==$item and return 1 for shift->items;
	return 0;
    });
}

__PACKAGE__->meta->make_immutable;
no Moose;

1;
