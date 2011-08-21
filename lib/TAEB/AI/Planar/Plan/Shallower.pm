package TAEB::AI::Planar::Plan::Shallower;
use TAEB::OO;
use Moose;
extends 'TAEB::AI::Planar::Plan';

# Aims towards dlvl 1. This plan is designed for reconnecting a broken
# dungeon graph (say, we just feel through a trapdoor), so it works on
# branch recognition and ignores the dungeon graph.
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
