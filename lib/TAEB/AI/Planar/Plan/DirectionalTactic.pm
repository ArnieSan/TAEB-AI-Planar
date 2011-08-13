#!/usr/bin/env perl
package TAEB::AI::Planar::Plan::DirectionalTactic;
use TAEB::OO;
use TAEB::Util qw/vi2delta refaddr/;
use Moose;
extends 'TAEB::AI::Planar::Plan::Tactical';

# Tactics that move one square on a level.
# The direction to move is stored in dir; for the purposes of tactical
# map precalculation, it can also be 's', meaning to treat all the
# directions in a symmetrical way if possible.
has (dir => (
    isa => 'Maybe[Str]',
    is  => 'rw',
    default => undef,
));
sub set_additional_args {
    my $self = shift;
    $self->dir(shift);
}

has (memorized_tile => (
    isa => 'Maybe[TAEB::World::Tile]',
    is => 'rw',
    default => undef,
));

# One additional note: calculate_risk is not allowed to break symmetry
# in a directional tactic, so tile_from and dir will not behave
# meaningfully when called from that function. Similar considerations
# apply to check_possibility.

# The tile to move to. When considering this "in the abstract", takes
# the tme as an argument. With no TME, assumes that the tile being
# moved from is the current tile (i.e. we're actually trying the
# action), and memorizes the tile in memorized_tile.
sub tile {
    my $self = shift;
    my $tme = shift;
    if (!defined $tme) {
        $self->memorized_tile(TAEB->current_tile->at_direction($self->dir));
        return $self->memorized_tile;
    }
    return $tme->{'tile_level'}->at($tme->{'tile_x'},$tme->{'tile_y'});
}
# The tile to move from. Takes the tme as an argument.
sub tile_from {
    my $self = shift;
    my $tme = shift;
    my ($dx, $dy) = vi2delta($self->dir);
    return $tme->{'tile_level'}->at($tme->{'tile_x'}-$dx,
                                    $tme->{'tile_y'}-$dy);
}

# Automatically memorize the tile when trying to perform the action.
before ('action' => sub {
    my $self = shift;
    $self->tile;
});

# add_possible_move, with an automatically calculated direction.
sub add_directional_move {
    my $self = shift;
    my $tme  = shift;
    $self->add_possible_move($tme, $self->dir);
}

# Matches the order in Tactical. If I use this more, it should
# be centralised somewhere (framework?)
use constant _vi_to_dindex => {y => 0, b => 1, u => 2, n => 3,
                               h => 4, l => 5, k => 6, j => 7};

# Directional plans don't have their difficulty checked by tactical
# routing, for efficiency reasons. Instead, when one goes wrong
# (without being abandoned), we go delete it from the cache, and it
# won't end up back there until the next full tactical recalculation
# after it becomes possible again. (TODO: schedule an FTR for the
# moment it becomes possible again.)
after ('mark_impossible' => sub {
    my $self = shift;
    return if $self->dir eq 's'; # don't wrap recursive calls
    my $ai = TAEB->ai;
    my $tile = $self->memorized_tile;
    my ($l, $x, $y) = ($tile->level, $tile->x, $tile->y);
    my $shortname = blessed $self;
    $shortname =~ s/^.*:://;

    # If the tactic is symmetrical, we want to mark the symmetrical
    # version impossible too (partly because it won't work in any
    # direction, partly because the directional version won't be
    # looked at). If it isn't, this is effectively a no-op, as it
    # updates a plan that nobody else will reference.
    $ai->get_tactical_plan($shortname, [$l, $x, $y, 's'])->mark_impossible;

    # NOT tme_from_tile; we want the raw version, not an updated one.
    my $tme = $ai->tactics_map->{refaddr $l}->[$x]->[$y];
    # Break the symmetry, if there is any.
    $self->add_possible_move($tme, "");

    # Now remove all instances of this tactic from the TME in question.
    my $dindex = _vi_to_dindex->{$self->dir};
    my $i = @{$tme->{'entry_tactics'}->[$dindex]};
    # We have to loop backwards here so that removing elements doesn't
    # mess up the loop counter. (Or we could loop forwards with an
    # adjustment, but that's more complex.)
    while ($i--) {
        if ($tme->{'entry_tactics'}->[$dindex]->[$i] eq $shortname) {
            # Remove it.
            splice @{$tme->{'entry_tactics'}->[$dindex]}, $i, 1;
            # And its matching spending plan.
            splice @{$tme->{'entry_spending_plans'}->
                         [$dindex]}, $i, 1;
        }
    }
});

use constant description => 'Using a tactic that moves one square';

__PACKAGE__->meta->make_immutable;
no Moose;

1;
