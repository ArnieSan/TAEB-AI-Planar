#!/usr/bin/env perl
package TAEB::AI::Planar::Plan::BCU;
use TAEB::OO;
use TAEB::Spoilers::Combat;
extends 'TAEB::AI::Planar::Plan::Strategic';

# We take an item in our inventory as argument.
has item => (
    isa     => 'Maybe[NetHack::Item]',
    is      => 'rw',
    default => undef,
);
sub set_arg {
    my $self = shift;
    $self->item(shift);
}

# The easiest-to-route altar.
sub aim_tile {
    my $self = shift;
    my $item = $self->item;
    $self->validity(0), return undef unless defined $item;
    $self->validity(0), return undef
        if $item->is_cursed || $item->is_uncursed || $item->is_blessed;
    return undef if TAEB->is_blind || TAEB->is_levitating;
    my $bestaltar = undef;
    my $bestaltarrisk = 1e6;
    my $ai = TAEB->ai;
    # nearest_level is used to iterate over levels.
    TAEB->dungeon->nearest_level(sub {
        my $level = shift;
        for my $altar ($level->tiles_of('altar')) {
            my $risk = $ai->tme_from_tile($altar)->numerical_risk;
            next unless $risk < $bestaltarrisk;
            $bestaltarrisk = $risk;
            $bestaltar = $altar;
        }
        return undef;
    });
    return $bestaltar;
}

sub has_reach_action { 1 }
sub reach_action {
    my $self = shift;
    my $item = $self->item;
    return undef unless defined $item;
    return TAEB::Action->new_action('drop', item => $item);
}

# The desire of BCUing an item. (Note that other plans can also /explicitly/
# request a BCU of an item, which will generally generate considerably more
# desire than 
sub gain_resource_conversion_desire {
    my $self = shift;
    my $item = $self->item;
    my $ai = TAEB->ai;
    my $resources = $ai->resources;
    my $benefit = 0;
    # Bump our own desirability.
    # Food is always generated uncursed, so it's pointless to BCU it
    # except incidentally.
    # Weapons are 10% likely to be cursed; armour's 13.18% likely.
    $item->type eq 'weapon'
        and $benefit = TAEB::Spoilers::Combat->damage($item)
                     * $resources->{'DamagePotential'}->value * 0.1;
    $item->type eq 'armor'
        and $benefit = ($item->ac // 0) * $resources->{'AC'}->value * 0.1318;
    $ai->add_capped_desire($self, $benefit);
}

sub calculate_extra_risk {
    my $self = shift;
    # TODO: More than this if we have to swap stuff out
    return $self->aim_tile_turns(1);
}

sub reach_action_succeeded {
    my $self = shift;
    my $item = $self->item;
    my $blocker = $self->taking_off;
    if ($blocker) {
        return 0 if $blocker->is_worn;
        return;
    }
    return 1 if $item->is_wielded || ($item->can('is_worn') && $item->is_worn);    
}

sub spread_desirability {
    my $self = shift;
    my $item = shift;
    $self->depends(1,'BCU',$item);
}

# This plan needs a continuous stream of validity from our inventory,
# or it ceases to exist.
sub invalidate {shift->validity(0);}

use constant description => "Checking an item's beatitude";

__PACKAGE__->meta->make_immutable;
no Moose;

1;
