#!/usr/bin/env perl
package TAEB::AI::Planar::Meta::Role::SqueezeChecked;

use TAEB::OO;
use Moose::Role;

# Mixing this role into a directional tactic causes it to refuse to
# attempt to move diagonally out of a doorway, or between two
# impassable squares.

requires 'add_possible_move';
requires 'tile';

use constant _virneighbors => {
    n => ['h','k'], b => ['l','k'], u => ['h','j'], y => ['l','j']
};
use constant _vireverse => {qw/y n n y u b b u h l l h j k k j/};

around ('add_possible_move' => sub {
    my $orig = shift;
    my $self = shift;
    my $tme = shift;
    my $dir = shift;
    defined $dir or die 'Roles were composed in the wrong order';
    my $tile = $self->tile($tme);
    my $ai = TAEB->ai;
    my $sokoban = TAEB->current_level->branch // '' eq 'sokoban';
    my $passable = $sokoban ? 'tile_walkable_or_boulder' : 'tile_walkable';

    $dir eq 's' and $dir = 'ybunhlkj';
    my @dir = split //, $dir;
    my $_;

    @dir = map {do{{ # just using {{...}} parses incorrectly
        /[hjkl]/o and last; # these are safe
        # We can't move from off the map.
        $tile->at_direction(_vireverse->{$_}) or ($_ = '', last);
        # We can't move diagonally out of a door.
        $tile->at_direction(_vireverse->{$_})->type eq 'opendoor'
            and ($_ = '', last);
        # We don't disallow squeezing if the square we move from is
        # impassable. (This helps to preserve symmetry.)
        $ai->$passable($tile->at_direction(_vireverse->{$_})) or last;
        # Otherwise, we're squeezing if both its orthogonal neighbours
        # are impassable.
        $ai->$passable($tile->at_direction(_virneighbors->{$_}->[0])) and last;
        $ai->$passable($tile->at_direction(_virneighbors->{$_}->[1])) and last;
        $_ = '';
    }}; $_} @dir;

    $dir = join '', @dir;
    $dir eq 'ybunhlkj' and $dir = 's';

    return unless $dir;
    $self->$orig($tme, $dir);
});

no Moose;

1;
