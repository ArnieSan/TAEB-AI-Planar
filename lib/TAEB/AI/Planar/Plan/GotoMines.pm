#!/usr/bin/env perl
package TAEB::AI::Planar::Plan::GotoMines;
use TAEB::OO;
use TAEB::Util qw/delta2vi/;
use Moose;
extends 'TAEB::AI::Planar::Plan::Strategic';
use List::MoreUtils 'all';

has (_level => (
    isa => 'Maybe[TAEB::World::Level]',
    is  => 'rw',
));

sub aim_tile {
    # If we're already in the Mines, bail.
    TAEB->current_level->known_branch && TAEB->current_level->branch eq 'mines'
        and return undef;

    # If we aren't in the Dungeons, bail.
    TAEB->current_level->known_branch && TAEB->current_level->branch eq 'dungeons'
        or return undef;

    shift->_level(TAEB->current_level);
    # Look for downstairs on this level.
    my @stairslist = ();
    TAEB->current_level->each_tile(sub {
        my $tile = shift;
        $tile->type eq 'stairsdown' && push @stairslist, $tile;});
    # If we know the other side goes to the Mines, use it.
    defined $_->other_side &&
        $_->other_side->known_branch && $_->other_side->branch eq 'mines'
        and return $_ for @stairslist;
    # If we're in the Dungeons, and there are two downstairs, the one we don't
    # know the other side of must go to the Mines. (Or be a mimic.)
    if ((scalar @stairslist) == 2) {
        defined $_->other_side && $_->other_side->known_branch
            or return $_ for @stairslist;
    }
    return undef;
}

sub has_reach_action { 1 }
sub reach_action {
    return TAEB::Action->new_action('descend');
}
sub reach_action_succeeded {
    my $self = shift;
    # If we went downstairs, it worked.
    return TAEB->current_level != $self->_level;
}

sub calculate_extra_risk {
    my $self = shift;
    return $self->cost('Time', 1);
}

sub spread_desirability {
    my $self = shift;
    # If we're in the Mines already, nothing we can do will help.
    TAEB->current_level->known_branch && TAEB->current_level->branch eq 'mines'
        and return;
    # If we aren't in the dungeons, go there.
    TAEB->current_level->known_branch && TAEB->current_level->branch eq 'dungeons'
        or $self->depends(1,"GotoDungeons"), return;

    my @d234 = grep { $_->known_branch && $_->branch eq 'dungeons' }
               map { TAEB->dungeon->get_levels($_) } 2,3,4;

    # Think about exploring all the levels that could have the fork.

    $self->depends(1, "ExploreLevel", $_) for (@d234);

    # If we don't have a full set of levels, head towards the missing
    # numbers

    my ($miss) = grep { my $level = $_;
        all { $_ != $level } -1, map { $_->z } @d234 } 2,3,4;

    $self->depends(1, "Descend") if defined $miss && $miss > TAEB->z;
    $self->depends(1, "Ascend")  if defined $miss && $miss < TAEB->z;
}

use constant description => 'Going to the Mines';
use constant references => ['ExploreLevel','Descend',
                            'Ascend','GotoDungeons'];

__PACKAGE__->meta->make_immutable;
no Moose;

1;
