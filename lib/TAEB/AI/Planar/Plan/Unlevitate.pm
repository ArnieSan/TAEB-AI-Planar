#!/usr/bin/env perl
package TAEB::AI::Planar::Plan::Unlevitate;
use TAEB::OO;
use TAEB::Util qw/delta2vi/;
use NetHack::Inventory::Equipment;
extends 'TAEB::AI::Planar::Plan::Strategic';

has taking_off => (
    isa     => 'Maybe[NetHack::Item]',
    is      => 'rw',
    default => undef,
);
has unwielding => (
    isa     => 'Bool',
    is      => 'rw',
    default => 0,
);


sub levitation_item {
    my $self = shift;
    for my $slot (NetHack::Inventory::Equipment->slots) {
        $_ = TAEB->inventory->equipment->$slot;
        next unless defined $_;
        return $_ if $_->identity =~ /\blevitation\b/;
    }
    return undef;
}

sub aim_tile {
    my $self = shift;
    my $item = $self->levitation_item;
    return undef unless defined $item;
    return undef if $item->is_cursed;
    $self->taking_off($item);
    return TAEB->current_tile;
}

sub has_reach_action { 1 }
sub reach_action {
    my $self = shift;
    my $item = $self->taking_off;
    return undef unless defined $item;
    my $slot = $item->subtype;
    my $blocker = TAEB->inventory->equipment->blockers($slot);
    if ($blocker && $blocker->type eq 'weapon') {
        $self->unwielding(1);
        return TAEB::Action->new_action('wield', weapon => 'nothing');
    }
    $self->unwielding(0);
    $self->taking_off($blocker);
    return TAEB::Action->new_action('remove',  item => $blocker)
        if $blocker;
    return TAEB::Action->new_action('remove',  item => $item);
}

sub calculate_extra_risk {
    my $self = shift;
    # TODO: More than this if we have to swap stuff out
    return $self->aim_tile_turns(1);
}

# This plan is always the "first half" of another plan. So it never
# succeeds, but can never be abandoned.
sub reach_action_succeeded {
    my $self = shift;
    my $item = $self->taking_off;
    if ($self->unwielding) {
        return 0 if TAEB->inventory->equipment->weapon;
        return;
    }
    if ($item) {
        return 0 if $item->is_worn;
        return;
    }
    return 0;
}
sub abandon {}

use constant description => 'Removing a levitation item';
use constant uninterruptible_by => ['Equip'];

__PACKAGE__->meta->make_immutable;
no Moose;

1;
