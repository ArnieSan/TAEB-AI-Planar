#!/usr/bin/env perl
package TAEB::AI::Planar::Plan::SokobanPrize;
use TAEB::OO;
use TAEB::Spoilers::Sokoban;
extends 'TAEB::AI::Planar::Plan';

has prizetile => (
    is => 'rw',
    isa => 'Maybe[TAEB::World::Tile]',
    default => undef,
);

# Gets us the Sokoban prize, with no restrictions on what we do with
# it after then.
sub spread_desirability {
    my $self = shift;
    my $level = TAEB->current_level;
    $self->prizetile(undef);
    if(TAEB::Spoilers::Sokoban->number_of_solved_sokoban_levels == 4) {
        my $sokotop = TAEB->dungeon->deepest_level(sub {
            my $level = shift;
            return $level->known_branch && $level->branch eq 'sokoban';
        });
        for my $item ($sokotop->items) {
            next unless $item->isa("NetHack::Item::Amulet")
                    || ($item->isa("NetHack::Item::Tool")
                     && $item->appearance eq 'bag');
            my $tile = $self->item_tile($item);
            next unless TAEB::Spoilers::Sokoban->
                            is_sokoban_reward_tile($tile);
            $self->depends(1,'PickupItem',$item);
            $self->prizetile($tile) if $tile == TAEB->current_tile;
        }
    }
}

use constant description => 'Getting the prize at the top of Sokoban';
use constant references => ['PickupItem'];

__PACKAGE__->meta->make_immutable;
no Moose;

1;