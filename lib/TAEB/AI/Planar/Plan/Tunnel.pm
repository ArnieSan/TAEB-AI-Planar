#!/usr/bin/env perl
package TAEB::AI::Planar::Plan::Tunnel;
use TAEB::OO;
use TAEB::Util qw/delta2vi/;
extends 'TAEB::AI::Planar::Plan::Tactical';

sub get_pick_and_time {
    my ($self) = @_;

    my $c = (TAEB->ai->plan_caches->{'Tunnel'} //= [undef, undef, -1]);
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
    return (@$c = (undef, undef, TAEB->ai->aistep)) if $eff_min < 0;

    return (@$c = ($pick, 100 / ($eff_min + 2) + 1, TAEB->ai->aistep));
}

has tile => (
    isa => 'Maybe[TAEB::World::Tile]',
    is  => 'rw',
    default => undef,
);
sub set_additional_args {
    my $self = shift;
    $self->tile(shift);
}

sub calculate_risk {
    my $self = shift;
    my $tme  = shift;
    my $tile = $self->tile;

    (undef, my $time) = $self->get_pick_and_time;

    $self->cost("Time", $time + 1); # we'll have to walk anyway
    $self->level_step_danger;
}

my %dig = ( wall => 1, rock => 1, closeddoor => 1 );
sub check_possibility_inner {
    my $self = shift;
    my $tme  = shift;
    my $tile = $self->tile;
    return if !$dig{ $tile->type } && !$tile->has_boulder;

    (my $pick, undef) = $self->get_pick_and_time;
    return unless $pick;

    return if $tile->in_shop;
    return if $tile->nondiggable;
    return if $tile->level->is_minetown;
    return if ($tile->level->branch // '') eq 'sokoban'; #XXX other nondig

    if (defined $tile->monster) {
	# We need to generate a plan to scare the monster out of the
	# way, if the AI doesn't want to kill it for some reason. Yes,
	# even if there's a wall on the same square. XXX code duplication
	$self->generate_plan($tme,"ScareMonster",$tile);
	return;
    }
    $self->add_possible_move($tme,$tile->x,$tile->y,$tile->level);
}

sub replaceable_with_travel { 0 }
sub action {
    my $self = shift;
    my $tile = $self->tile;
    my $dir = delta2vi($tile->x - TAEB->x, $tile->y - TAEB->y);
    (my $pick, undef) = $self->get_pick_and_time;

    if (!defined $dir) {
	die "Could not move from ".TAEB->x.", ".TAEB->y." to ".
	    $tile->x.", ".$tile->y." because they aren't adjacent.";
    }

    return TAEB::Action->new_action(
	'apply', direction => $dir, item => $pick);
}

sub succeeded {
    my $self = shift;
    return $self->tile->is_walkable(0,1);
}

use constant description => 'Digging through a wall';
use constant references => ['ScareMonster'];

__PACKAGE__->meta->make_immutable;
no Moose;

1;
