#!/usr/bin/env perl
package TAEB::AI::Planar::Plan::FloorFood;
use TAEB::OO;
use TAEB::Util qw/delta2vi/;
use TAEB::Spoilers::Monster;
extends 'TAEB::AI::Planar::Plan::Strategic';

# We take an item, or a spoiler and tile, as argument.
has item => (
    isa     => 'Maybe[NetHack::Item]',
    is  => 'rw',
    default => undef,
);
has tile => (
    isa     => 'Maybe[TAEB::World::Tile]',
    is  => 'rw',
    default => undef,
);
has spoiler => (
    isa     => 'Maybe[HashRef]',
    is  => 'rw',
    default => undef,
);
sub set_arg {
    my $self = shift;
    my $arg = shift;
    if(ref $arg eq 'ARRAY') {
	$self->item(undef);
	$self->tile($arg->[0]);
	$self->spoiler($arg->[1]);
    } else {
	$self->item($arg);
	$self->tile($self->item_tile($arg));
	$self->spoiler(TAEB::Spoilers::Monster->monster($arg->monster));
    }
}

sub aim_tile {
    my $self = shift;
    return undef unless defined $self->item;
    return $self->tile;
}

sub has_reach_action { 1 }
sub reach_action {
    my $self = shift;
    return undef unless defined $self->item;
    return TAEB::Action->new_action('eat', food => $self->item);
}
# TODO: reach_action_succeeded

# This is resource conversion: we gain the food, for free more or less.
# The time spent pathing to and eating it is risk rather than resource
# loss.
sub gain_resource_conversion_desire {
    my $self = shift;
    my $ai   = TAEB->ai;
    # Bump our own desirability.
    $ai->add_capped_desire($self, $ai->resources->{'Nutrition'}->value *
			   $self->spoiler->{'corpse'}->{'nutrition'});
}

# The number of turns it takes to eat a corpse is equal to 3 plus
# its weight shifted right 6 places.
has _risk => (
    isa => 'Num',
    is  => 'rw',
    default => 0,
);
sub calculate_extra_risk {
    my $self = shift;
    my $risk = 0;
    my $corpse = $self->spoiler->{'corpse'};
    # Certain corpses are a lot more risky.
    # TODO: Work out a sensible way to quantify this risk.
    $risk += 1000 if defined $self->item && $self->item->maybe_rotted > -1;
    $risk += 1000 if $corpse->{'die'};
    $risk += 1000 if $corpse->{'lycanthropy'};
    $risk += 1000 if $corpse->{'petrify'};
    $risk += 1000 if $corpse->{'polymorph'};
    $risk += 1000 if $corpse->{'slime'};
    $risk += 1000 if $corpse->{'hallucination'};
    $risk += 1000 if $corpse->{'poisonous'};
    $risk += 1000 if $corpse->{'stun'};
    $risk += 1000 if $corpse->{'cannibal'} eq TAEB->race;
    $risk += 1000 if $corpse->{'aggravate'};
    # TODO: Make this the cost of the intrinsic
    $risk += 1000 if $corpse->{'speed_toggle'};
    # Acidic corpses just deal damage, so they cost in hitpoints.
    $risk += $self->cost('Hitpoints', 15) if $corpse->{'acidic'};
    $self->_risk($risk + $self->aim_tile_turns(3+$corpse->{'weight'}>>6));
    return $self->_risk;
}

# This plan only exists while there is actually a corpse to eat.
# In otherwords, it needs to be generated every step from either
# GroundItemMeta or Investigate.
sub invalidate {shift->validity(0);}

# If we don't know for sure that the corpse is there, this plan
# is always-fail; but we spread desirability minus risk to an
# appropriate Investigate plan.
sub spread_desirability {
    my $self = shift;
    return if defined $self->item;
    # We need to revert a fail-fast 0, if there was one.
    # This is accomplished by setting desire_with_risk to its true
    # value, calculable using $self->_risk.
    my $true_dwr = $self->desire - $self->_risk;
    $self->desire_with_risk($true_dwr);
    $self->depends_risky(1,"Investigate",$self->tile);
}

use constant description => 'Eating a corpse on the floor';
use constant references => ['Investigate'];

__PACKAGE__->meta->make_immutable;
no Moose;

1;
