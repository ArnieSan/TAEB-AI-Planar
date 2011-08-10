#!/usr/bin/env perl
package TAEB::AI::Planar::Plan::Kill;
use TAEB::OO;
use Moose;
extends 'TAEB::AI::Planar::Plan';

# There are 3 plans in Planar that are involved in the removal of monsters.
#
# Kill- I want this monster dead, in front of me, and in my kill list.  Will
#   delegate to Melee, Projectile, etc, etc.  Usually you won't use this; it
#   is capable of generating resource conversion desire for the monster's XP,
#   corpse, and expected loot.
#
# Eliminate- I want this monster to not be in front of me anymore.  Use this
#   if you need to get past it.  It could Kill, or it could scare it away, or
#   zap a wand of teleportation, or tame and swap places, or...
#
# Mitigate- This monster is threatening me.  Make it stop.  This might involve
#   healing ourselves, or writing E on the ground, or paralyzing it, none of
#   which will help us get past it.

# We take a monster as argument.
has (monster => (
    isa     => 'Maybe[TAEB::World::Monster]',
    is  => 'rw',
    default => undef,
));
sub set_arg {
    my $self = shift;
    $self->monster(shift);
}

sub spread_desirability {
    my $self = shift;
    $self->depends(1,"Melee",$self->monster);
    $self->depends(1,"Projectile",$self->monster);
    $self->depends(1,"AttackSpell",$self->monster);
}

# XXX this probably belongs in a spoiler file
my @loot = (
    ['hobbit'] =>
	[ 1/3 => 'elven dagger',
	  1/3 => 'sling',
	  1/3 => 'dagger',
	  0.1 => 'elven mithril-coat',
	  0.1 => 'dwarvish cloak' ],
    ['dwarf', 'dwarf lord', 'dwarf king'] =>
	[ 6/7 => 'dwarvish cloak',
	  6/7 => 'iron shoes',
	  1/4 => 'dwarvish short sword',
	  1/8 => 'dwarvish mattock',
	  1/8 => 'axe',
	  1/8 => 'dwarvish roundshield',
	  1/4 => 'dwarvish iron helm',
	  1/12=> 'dwarvish mithril-coat',
	  1/2 => 'dagger',
	  1/4 => 'pick-axe' ],
    ['goblin'] =>
	[ 1/2 => 'orcish helm',
	  1/2 => 'orcish dagger' ],
);

my %loot;
while (my ($mons, $table) = splice @loot, 0, 2) {
    $loot{$_} = $table for (@$mons);
}

sub gain_resource_conversion_desire {
    # XXX XP
    # XXX corpses
    my $self = shift;
    my $mon = $self->monster;
    my $spoiler = $mon->spoiler // return; # don't bother chasing down Is

    my $value = 0;

    my $corpse = $spoiler->corpse_type;

    if (!$corpse->never_drops_corpse) { #XXX poison, etc
	$value += TAEB->ai->resources->{'Nutrition'}->value *
	    $corpse->corpse_nutrition;
    }

    my @types = @{ $loot{$spoiler->name} // [] };

    while (my ($freq, $item) = splice @types, 0, 2) {
	$value += $freq * TAEB->ai->item_value(TAEB->new_item($item));
    }

    TAEB->ai->add_capped_desire($self, $value);
}

sub invalidate {shift->validity(0);}

use constant description => "Killing something that we want to die";
use constant references => ['Melee','Projectile','AttackSpell'];

__PACKAGE__->meta->make_immutable;
no Moose;

1;
