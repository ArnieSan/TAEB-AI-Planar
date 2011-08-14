#!/usr/bin/env perl
package TAEB::AI::Planar::Plan::Tunnel;
use TAEB::OO;
use TAEB::Util qw/delta2vi/;
use Moose;
extends 'TAEB::AI::Planar::Plan::DirectionalTactic';

has (unequipping => (
    isa => 'Bool',
    is  => 'rw',
    default => 0,
));

sub get_pick_and_time {
    my ($self) = @_;

    my $c = (TAEB->ai->plan_caches->{'Tunnel'} //= [undef, undef, -1, 0]);
    return @$c if $c->[2] == TAEB->ai->aistep;

    my @picks = map { [ ($_->numeric_enchantment // 0) -
#                        $_->greatest_erosion, $_ ] }
                        ($_->burnt + $_->rusty > $_->rotted + $_->corroded ?
                         $_->burnt + $_->rusty : $_->rotted + $_->corroded), $_ ] }
	TAEB->inventory->find(['pick-axe', 'dwarvish mattock']);

    return (@$c = (undef, undef, TAEB->ai->aistep)) unless @picks;

    my ($effective, $pick) = @{ ((sort { $a->[0] <=> $b->[0] } @picks)[0]) };

    my $eff_min = 10 + $effective + TAEB->accuracy_bonus +
	TAEB->item_damage_bonus;

    # doing this right requires scary math, like, gambler's ruin theorem scary

    # actually possible, but I don't want to think about the time
    return (@$c = (undef, undef, TAEB->ai->aistep, undef)) if $eff_min < 0;

    my $time = 100 / ($eff_min + 2) + 1;
    # It costs 1 unit of time to walk after digging, and 1 to rewield
    # our weapon. 2 more if we have to unwield and rewield a shield too.
    my $timecost = $time + 2;
    $timecost += 2 if $pick->hands == 2 && TAEB->inventory->equipment->shield;
    return (@$c = ($pick, $time, TAEB->ai->aistep, $timecost));
}

sub has_pick {
    my ($self) = @_;
    my ($pick) = get_pick_and_time;
    return $pick;
}

sub calculate_risk {
    my $self = shift;
    my $tme  = shift;

    (undef, undef, undef, my $timecost) = $self->get_pick_and_time;

    $self->cost("Time", $timecost);
    $self->level_step_danger($tme->{'tile_level'});
}

my %dig = ( wall => 1, rock => 1, closeddoor => 1 );
sub check_possibility {
    my $self = shift;
    my $tme  = shift;
    my $tile = $self->tile($tme);
    return if !$dig{ $tile->type } && !$tile->has_boulder;

    # Don't dig in sight of monsters (including peacefuls, they tend to
    # get annoyed at it)
    return if $tile->level->monster_count;

    (my $pick, undef, undef, undef) = $self->get_pick_and_time;
    return unless defined $pick;

    return if $tile->nondiggable;
    return if $tile->level->is_minetown;
    return if ($tile->level->branch // '') eq 'sokoban'; #XXX other nondig


    # Don't dig near a shop
    return if $tile->any_diagonal( sub { shift->in_shop; } );

    $self->add_directional_move($tme);
}

sub replaceable_with_travel { 0 }
sub action {
    my $self = shift;
    $self->tile; # memorize it
    (my $pick, undef, undef, undef) = $self->get_pick_and_time;

    if ($pick->hands == 2) {
        # To use a mattock, we need to unequip a shield first.
        my $shield = TAEB->inventory->equipment->shield;
        if ($shield) {
            $self->unequipping(1);
            return TAEB::Action->new_action(
                'remove', item => $shield);
        }
    }

    $self->unequipping(0);
    return TAEB::Action->new_action(
	'apply', direction => $self->dir, item => $pick);
}

sub succeeded {
    my $self = shift;
    if ($self->unequipping) {
        return undef unless TAEB->inventory->equipment->shield;
        return 0;
    }
    # Don't use tile_walkable here, it'll have a cached value from
    # the wrong aistep
    return $self->memorized_tile->is_walkable(0,1);
}

use constant description => 'Digging through a wall';
use constant uninterruptible_by => ['Equip','PickupItem'];

__PACKAGE__->meta->make_immutable;
no Moose;

1;
