#!/usr/bin/env perl
package TAEB::AI::Planar::Resource::Ammo;
use TAEB::OO;
extends 'TAEB::AI::Planar::Resource';

has _value => (
    isa => 'Num',
    is  => 'rw',
    default => 15, # one ammo is quite a lot compared to 1 turn or 1 nutrition
);

# Split out from amount to avoid code duplication; other things care
# about which projectiles we have too
sub projectilelist {
    my @projectiles;
    for my $type (qw/dagger spear shuriken dart/) {
	push @projectiles, (TAEB->inventory->find(
                           identity   => qr/\b$type\b/,
                           is_wielded => sub { !$_ },
                           cost       => 0,
                       ));
    }
    return @projectiles;
}
sub amount {
    return scalar projectilelist;
}

# Ammo is less useful the more we have.
sub scarcity {
    my $self = shift;
    my $quantity = shift;
    return 1 if $quantity < 5;
    return 0.8 if $quantity < 10;
    return 0.6 if $quantity < 15;
    return 0.4 if $quantity < 20;
    return 0.2 if $quantity < 25;
    return 0.1;
}

__PACKAGE__->meta->make_immutable;
no Moose;

1;
