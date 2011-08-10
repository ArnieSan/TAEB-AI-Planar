package TAEB::AI::Planar::Plan::Shallower;
use TAEB::OO;
use Moose;
extends 'TAEB::AI::Planar::Plan';

# Note that this plan works on branch-recognition, not the dungeon
# graph. That's because it's designed to be suitable for reconnecting
# a broken dungeon graph (among other things; it would also be
# suitable for the ascension run, although just pathing to the first
# level upstairs would be a more robust way to do that).
sub spread_desirability {
    my $self = shift;
    my $plan = 'AscendAvoidingBranches';
    if (TAEB->current_level->known_branch) {
        $plan = 'Descend' if TAEB->current_level->branch eq 'sokoban';
    }
    $self->depends(1,$plan)
        if $plan ne 'AscendAvoidingBranches' || TAEB->current_level->z != 1;
}

use constant description => 'Aiming towards the top of the dungeon';
use constant references  => ['AscendAvoidingBranches','Descend'];

__PACKAGE__->meta->make_immutable;
no Moose;

1;
