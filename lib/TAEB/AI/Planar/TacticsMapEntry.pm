#!/usr/bin/env perl
package TAEB::AI::Planar::TacticsMapEntry;

=begin comment

This is an unencapsulated object for performance reasons. (It's about
a 33% speedup in the tactical mapping, 20% in the bot as a whole, so
it's pretty much necessary. Objects here are created by blessing
hashes in the caller; a TME isn't designed to be modified once
created, although that could be possible to. Therefore, there is
nothing in the package apart from one method. As an unencapsulated
class can be very hard to use, though, without at least some guide as
to what it's meant to look like, a Moosish version is provided in this
massive comment as a guide.

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

# The risk of stepping onto this tile (= cost + danger).
# This is a hash whose keys are resource names and whose values are
# the amount of that resource it costs.
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

# The tactical plan used to step onto this tile from the previous one.
# This is try()ed to get the action that is needed to step here.
has tactic => (
    isa => 'Maybe[TAEB::AI::Plan]',
    default => undef,
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

# The step on which this TME was last updated.
has step => (
    isa => 'Int',
);

=end comment

=cut

sub numerical_risk {
    my $self = shift;
    my $risk = 0;
    my $tpr = TAEB->ai->resources;
    $risk += $tpr->{$_}->cost($self->{'risk'}->{$_})
	for keys %{$self->{'risk'}};
    return $risk;
}

1;
