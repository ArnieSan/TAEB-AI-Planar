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
# looks like [level, x, y], or often [level, x, y, direction] for
# plans like Walk which are coming from somewhere and going to
# somewhere. The level, x, and y are stored as a TME, but not passed
# that way, and represent the square being moved /to/ for a
# directional plan and /from/ for a complex plan. (Basically, they're
# given the TME the plan is stored in.)
sub set_arg {
    my $self = shift;
    my @args = @{(shift)};
    splice @args, 0, 3;
    $self->set_additional_args(@args);
}
# Directional tactics get a vikeys direction here (including 's' to
# indicate that they should try to handle all 8 directions at once).
# Complex tactics get the tile they're moving to.
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

# Impossibility for tactical plans is based on the tactical success
# count.
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
after (reactivate_dependencies => sub {
    my $self = shift;
    $self->toxic_until(-1);
});

# Some tactical plans can be replaced by travelling instead, to save
# time. This should be set to 1 if a travel to the destination of the
# TME would have much the same effect as doing it via actions.
sub replaceable_with_travel { 0 }

# The main entry point for tactical planning. This causes the plan to
# either call add_possible_move to add a possible move from where it
# is at the moment, or to call check_possibility on other plans if
# this is a metaplan (as opposed to spawning via planspawn), most
# likely indirectly via generate_plan. Note that due to symmetry
# optimisation, directional plans which allow 's' for symmetry as a
# direction won't necessarily be able to persist data between
# check_possibility and, say, action, but that's a dubious thing to be
# doing anyway. This isn't an issue for nondirectional plans.
#
# For metaplans (MoveTo and MoveFrom), this is called as a class
# method for optimisation reasons, and so it can only refer to
# methods like generate_plan and tme_tile that don't care about
# properties of the caller.
sub check_possibility {
    die "All tactical plans must override check_possibility";
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

# Matches the order in TAEB::Util::deltas (and must do so)
use constant _vi_to_dindex => {y => 0, b => 1, u => 2, n => 3,
                               h => 4, l => 5, k => 6, j => 7};

# add_possible_move on the plan updates the given TME to add this plan
# as a possible one for moving to that TME in the given direction
# (enter_vidir = a vikeys direction), or from that TME in a more
# complex way (enter_vidir = undef).
sub add_possible_move {
    my $self = shift;
    my $tme = shift;
    my $pkg = blessed $self || $self;
    # vi direction(s) to enter this tile via, or 's' if the plan allows
    # entering from any walkable tile
    my $enter_vidir = shift;

    if (!defined $enter_vidir) {
        # It's not a directional plan...
        push @{$tme->{'other_tactics'}}, $self;
        return;
    }

    $pkg =~ s/^.*:://o; # remove everything up to and including the last ::

    if ($enter_vidir eq 's') {
        $enter_vidir = 'ybunhlkj';
    } elsif ($tme->{'is_symmetrical'}) {
        $tme->{'is_symmetrical'} = 0;
        my $sp = $tme->{'entry_spending_plans'}->[0];
        do {my @sp = @$sp; $tme->{'entry_spending_plans'}->[$_] = \@sp;}
        for 1..7;
    }

    # Optimise use of this to merely break symmetry.
    return if $enter_vidir eq '';

    # Don't add the tactic if it's currently considered impossible.
    return if $self->difficulty;

    $self->next_plan_calculation;
    $self->spending_plan({});
    $self->calculate_risk($tme);

    my %nsp = %{$self->spending_plan};

    my $symlimit = $tme->{'is_symmetrical'} ? 0 : 7;

    for my $dir (split //, $enter_vidir) {
        my $i = _vi_to_dindex->{$dir};
        push @{$tme->{'entry_tactics'}->[$i]}, $pkg;
        $i <= $symlimit and
            push @{$tme->{'entry_spending_plans'}->[$i]}, \%nsp;
    }
}

__PACKAGE__->meta->make_immutable;
no Moose;

1;
