#!/usr/bin/env perl
package TAEB::AI::Planar::Plan::AttackSpell;
use TAEB::OO;
use TAEB::Util qw/delta2vi/;
use TAEB::AI::Planar::Resource::FightDamage;
use POSIX qw/ceil/;
extends 'TAEB::AI::Planar::Plan::Strategic';

# We take a monster as argument.
has monster => (
    isa     => 'Maybe[TAEB::World::Monster]',
    is  => 'rw',
    default => undef,
);

sub set_arg {
    my $self = shift;
    $self->monster(shift);
}

sub get_spell {
    my $spell;

    if (defined ($spell = TAEB->find_spell('force bolt'))
        && $spell->castable)
    {
        return $spell;
    }

    $projectile and return $projectile;
    return;
}

# To throw projectiles, we're aiming for a tile orthogonal or diagonal
# to the monster.
sub aim_tile {
    my $self = shift;
    return $self->monster->tile if $self->get_spell;
    return undef;
}

sub stop_early {
    return 6;
    # XXX actually rn1(8,6) for force bolt
}

sub stop_early_blocked_by {
    my $self = shift;
    my $tile = shift;
    my $monster = $self->monster;
    return 1 if $tile->type eq 'rock' && !$tile->has_boulder;
    return 1 if $tile->type eq 'wall';
    return 1 if $tile->has_monster;
    return 1 if $tile->type eq 'sink';
    return 1 if $tile->type eq 'unexplored'
             && $monster->glyph eq 'I' || TAEB->is_blind;
    return 0;
}

sub mobile_target { 1 }
sub has_reach_action { 1 }

sub reach_action {
    my $self = shift;
    my $aim = $self->aim_tile;
    my $dir = delta2vi($aim->x-TAEB->x <=> 0, $aim->y-TAEB->y <=> 0);

    return undef unless $dir =~ /[yuhjklbn]/;

    return TAEB::Action->new_action('cast',
                                    spell => $self->get_spell,
                                    target_tile => $aim,
                                    direction => $dir);
}

sub calculate_extra_risk {
    my $self = shift;
    my $fd = TAEB->ai->resources->{'FightDamage'};

    my $risk = $self->cost("FightDamage",
        $fd->spell_damage(TAEB->power) - $fd->spell_damage(TAEB->power - 5));

    my $damage = $fd->force_bolt_damage
        * (100 - $self->get_spell->failure_rate) / 100;

    my $monster = $self->monster;

    $risk += $self->aim_tile_turns(
        ceil($monster->average_actions_to_kill($damage) // 3) || 1);

    # Chasing unicorns is fruitless
    $risk += $self->cost("Impossibility", 1) if $monster->is_unicorn &&
        $self->aim_tile_cache != $self->aim_tile;

    $risk += $self->attack_monster_risk($monster) // 0;
    $risk += $self->cost("Pacifism", 1);
    return $risk;
}

# Writing Elbereth before melee tends to just scare monsters off.
# XXX monster tracking, ekiM
sub elbereth_helps { 0 }

# Invalidate ourselves if the monster stops existing.
sub invalidate { shift->validity(0); }

use constant description => 'Casting spells at a monster';

__PACKAGE__->meta->make_immutable;
no Moose;

1;
