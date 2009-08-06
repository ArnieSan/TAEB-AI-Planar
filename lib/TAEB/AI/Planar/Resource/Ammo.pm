#!/usr/bin/env perl
package TAEB::AI::Planar::Resource::Ammo;
use TAEB::OO;
extends 'TAEB::AI::Planar::Resource';

has _value => (
    isa => 'Num',
    is  => 'rw',
    default => 20, # one ammo is quite a lot compared to 1 turn or 1 nutrition
);

# Split out from amount to avoid code duplication; other things care
# about which projectiles we have too
sub projectilelist {
    my $daggers = shift;
    my @projectiles;
    for my $type ($daggers ? 'dagger' : qw/dagger spear shuriken dart rock/) {
	push @projectiles, (TAEB->inventory->find(
                           identity   => qr/\b$type\b/,
                           is_wielded => sub { !$_ },
                           cost       => 0,
                       ));
    }
    return @projectiles;
}
sub amount {
    return (scalar projectilelist 1) * 0.9 + (scalar projectilelist 0) * 0.1;
}

# Ammo is less useful the more we have.
sub scarcity {
    my $self = shift;
    my $quantity = shift;
    return 4 if $quantity < 5;
    return 2 if $quantity < 10;
    return 1 if $quantity < 15;
    return 0.5 if $quantity < 20;
    return 0.2 if $quantity < 25;
    return 0.1;
}

__PACKAGE__->meta->make_immutable;
no Moose;

1;
