#!/usr/bin/env perl
package TAEB::AI::Planar::Plan::EnterShop;
use TAEB::OO;
use TAEB::Util qw/delta2vi/;
use TAEB::AI::Planar::Plan::Tunnel;
use Moose;
extends 'TAEB::AI::Planar::Plan::Strategic';

# The item we're trying to drop in order to enter the shop.
has (pick => (
    isa     => 'Maybe[NetHack::Item]',
    is      => 'rw',
    default => undef,
));

# Our argument is a shop doorway.
has (doorway => (
    isa     => 'Maybe[TAEB::World::Tile]',
    is      => 'rw',
    default => undef,
));
sub set_arg {
    my $self = shift;
    $self->doorway(shift);
}

sub droptile_direction {
    my $self = shift;
    my $door = $self->doorway;
    # In theory, there can be a shop door at the edge of the map
    # if someone made one with a digging tool, wand of locking, and
    # we encounter a bones file.
    return 'l' if $door->y > 1  and $door->at_direction('h')->in_shop;
    return 'k' if $door->x < 79 and $door->at_direction('j')->in_shop;
    return 'j' if $door->x > 0  and $door->at_direction('k')->in_shop;
    return 'h' if $door->y < 21 and $door->at_direction('l')->in_shop;
    die "Shop disappeared in EnterShop";
}

sub aim_tile {
    my $self = shift;
    my $pick = TAEB::AI::Planar::Plan::Tunnel->has_pick;
    $self->pick($pick);
    return undef unless defined $pick;
    return undef if !$pick->can_drop;
    return $self->doorway->at_direction($self->droptile_direction);
}

sub has_reach_action { 1 }
sub reach_action {
    my $self = shift;
    my $pick = $self->pick;
    return undef unless defined $pick;
    return TAEB::Action->new_action('drop', items => [$pick]);
}

sub calculate_extra_risk {
    my $self = shift;
    return $self->aim_tile_turns(1);
}

sub reach_action_succeeded {
    my $self = shift;
    my $pick = $self->pick;
    defined $pick->slot and TAEB->inventory->get($pick->slot) and return 0;
    # We might have more than one pickaxe.
    TAEB::AI::Planar::Plan::Tunnel->has_pick and return undef;
    return 1;
}

use constant description => 'Entering a shop';
use constant references => ['PickupItem'];
use constant unfollowable_by => ['PickupItem'];

__PACKAGE__->meta->make_immutable;
no Moose;

1;
