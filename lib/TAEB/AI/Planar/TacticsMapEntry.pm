#!/usr/bin/env perl
package TAEB::AI::Planar::TacticsMapEntry;
use Exporter 'import';
@EXPORT_OK = qw/numerical_risk_from_spending_plan/;

=begin comment

This is an unencapsulated object for performance reasons. (It's about
a 33% speedup in the tactical mapping, 20% in the bot as a whole, so
it's pretty much necessary. Objects here are created by blessing
hashes in the caller. Therefore, there is nothing in the package apart
from one method and one function. As an unencapsulated class can be
very hard to use, though, without at least some guide as to what it's
meant to look like, a Moosish version is provided in this massive
comment as a guide.

# Details of the tile we have to path to before we can path to this
# one. Calculating a path is done by tracing the prevtile chain back
# to the player. There is also a prevlevel chain, to make interlevel
# pathing work correctly. These stay at undef if there is no previous
# tile/level, or if we haven't figured out a path to reach this tile
# yet. (The prevlevel chain is updated lazily, not every step.)
has prevtile_level => (
    isa => 'Maybe[TAEB::World::Level]',
    default => undef,
);
has prevtile_x => (
    isa => 'Maybe[Int]',
    default => undef,
);
has prevtile_y => (
    isa => 'Maybe[Int]',
    default => undef,
);
has prevlevel_level => (
    isa => 'Maybe[TAEB::World::Level]',
    default => undef,
);
has prevlevel_x => (
    isa => 'Maybe[Int]',
    default => undef,
);
has prevlevel_y => (
    isa => 'Maybe[Int]',
    default => undef,
);

# The step on which this TME was last updated.
has step => (
    isa => 'Int',
);

# The step on which this TME was last added to the tactics heap.
# (This is used to identify if it's on the tactics heap at the
# moment.)
has considered => (
    isa => 'Int',
);

# The risk of stepping onto this tile (= cost + danger), relative to
# the player's current location on step step. This is a hash whose
# keys are resource names and whose values are the amount of that
# resource it costs (i.e., a spending plan).
has risk => (
    isa => 'HashRef[Num]',
    default => sub { {} },
);

# The risk of pathing to this tile /within the level/, calculated the
# same way as the risk value above. This is to allow level caching to
# work, and again is updated lazily.
has level_risk => (
    isa => 'HashRef[Num]',
    default => sub { {} },
);

# The tactic used to enter this TME (only valid if step==aistep).
has tactic => (
    isa => 'TAEB::AI::Planar::Plan::Tactical',
);

# The tactical plan classes that are needed to enter this tile in each
# of the directions, in the order in TAEB::Util::deltas; that is,
# ybunhlkj (i.e. "y" means "enter by going northwest"). More than one
# plan might be possible for a particular movement, or none at all, so
# we use a varying-length ArrayRef which lists the plans in no
# particular order (using a Set would be semantically correct but
# overkill. The class names are just the last component (after
# TAEB::AI::Planar::Plan::), not the full name.
has entry_tactics => (
    isa => 'ArrayRef[ArrayRef[Str]]',
);

# The spending plans for entering this tile from each of the
# directions. As above, but with spending plans instead of
# names. If the plan is symmetrical, this has length 1 not 8; it's
# expanded when symmetry is broken. The spending plans themselves
# may well share, and so should be treated as immutable (i.e. copy
# and replace the hash if you need to change it, don't change
# individual elements in it).
has entry_spending_plans => (
    isa => 'ArrayRef[ArrayRef[HashRef[Num]]]',
);

# Tactics for leaving this tile in ways more complex than can be
# represented by the entry_tile mechanism.
has other_tactics => (
    isa => 'ArrayRef[TAEB::AI::Planar::Plan::Tactical]'
);

# Optimisation: in the common case, entering a tile works the same way
# no matter where you're coming from. (This is not necessarily the
# case for, e.g, doorways, or squares you have to squeeze to enter.)
# This boolean just flags whether that's the case or not; leaving it
# as false is always fine, but setting it to true will make the code
# more efficient (and incorrect in the case that it isn't actually
# symmetrical). update_tactical_map initialises this to true; it's the
# responsibility of tactical plans to set it to false if they break
# symmetry (which add_possible_move will do automatically if given an
# asymmetrical movement specification).
has is_symmetrical => (
    isa => 'Bool',
);

# The tile that this entry refers to.
has tile_x => (
    isa => 'Int',
);
has tile_y => (
    isa => 'Int',
);
has tile_level => (
    isa => 'TAEB::World::Level',
);

# The plans that could potentially make this tile less dangerous.
# (This is generally Eliminating nearby monsters.) It's a hash ref
# whose keys are the plans and whose value is the amount of risk that
# would be eliminated if the plan were carried out, from the point of
# view of stepping onto this tile.
# When calculating the risk of a path, this is accumulated along the
# path; therefore, the small amounts of risk this gives will add up
# over time and distance. Such plans also have a risk multiplier on
# them if we seem likely to cross the area more than once (which is
# the case everywhere but the Planes, more or less). Note that these
# plans are /strategic/ plans.
has make_safer_plans => (
    isa => 'Maybe[HashRef[Num]]',
    default => sub { {} },
);

# Whether this TME is tainted. Taintedness is only used by certain
# routing algorithms; its generic meaning is that tainted TMEs can
# only generate other tainted TMEs, and when all TMEs are tainted
# it stops routing.
has taint =>
    isa => 'Bool',
);

# What routing algorithm, and what stage of that algorithm, was
# last used to update this TME.
has source =>
    isa => 'Str',
);

=end comment

=cut

sub numerical_risk_from_spending_plan {
    my $tpr = TAEB->ai->resources;
    my $sp = shift;
    my $risk = 0;
    $risk += $tpr->{$_}->cost($sp->{$_}) for keys %$sp;
    return $risk;
}

sub numerical_risk {
    my $self = shift;
    return numerical_risk_from_spending_plan($self->{'risk'});
}

1;
