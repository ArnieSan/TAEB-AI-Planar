#!/usr/bin/env perl
package TAEB::AI::Planar::Resource::FightDamage;
use TAEB::OO;
extends 'TAEB::AI::Planar::Resource';

# This encapsulates all damage sources that are usable once per fight;
# primarily, throwables and spells.

has _value => (
    isa => 'Num',
    is  => 'rw',
    default => 8, # Fairly large
);

# Split out from amount to avoid code duplication; other things care
# about which projectiles we have too
sub projectilelist {
    my @projectiles;
    for my $type (qw/dagger spear shuriken dart rock/) {
        push @projectiles, (TAEB->inventory->find(
                            identity   => qr/\b$type\b/,
                            is_wielded => sub { !$_ },
                            cost       => 0,
                           ));
    }
    return @projectiles;
}

# XXX once the design is more stable, this should be moved into framework
sub force_bolt_damage
{
    my $damage = 13;

    if (TAEB->int < 10)
    {
        $damage -= 3;
    }
    elsif (TAEB->level < 5 || TAEB->int < 14)
    {
    }
    elsif (TAEB->int <= 18)
    {
        $damage++;
    }
    else
    {
        $damage += 2;
    }

    return $damage;
}

sub spell_damage
{
    my $self = shift;
    my $power = shift;
    my @equip = @_;
    my $spell;
    my $amt = 0;

    if (defined($spell = TAEB->find_spell("force bolt"))
        && $spell->castable)
    {
        my $casts = int($power / 5);

        my $damage = force_bolt_damage;

        $amt += $casts * $damage * (100 - $spell->failure_rate(@equip)) / 100;

        $power -= $casts * 5;
    }

    return $amt;
}

sub amount {
    my $amt = 0;
    my $self = shift;

    for my $proj (projectilelist) {
        $amt += TAEB::Spoilers::Combat->damage($proj);
    }

    $amt += $self->spell_damage(TAEB->power);

    return $amt;
}

# Ammo is less useful the more we have.
sub scarcity {
    my $self = shift;
    my $quantity = shift;
    return 1 if $quantity < 20;
    return 0.5 if $quantity < 40;
    return 0.25 if $quantity < 60;
    return 0.125 if $quantity < 80;
    return 0.05 if $quantity < 100;
    return 0.025;
}

__PACKAGE__->meta->make_immutable;
no Moose;

1;
