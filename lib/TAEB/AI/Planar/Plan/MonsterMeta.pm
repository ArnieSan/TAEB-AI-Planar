#!/usr/bin/env perl
package TAEB::AI::Planar::Plan::MonsterMeta;
use TAEB::OO;
extends 'TAEB::AI::Planar::Plan';

# A plan that does nothing but create other plans, as appropriate to
# the item in question.

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

# Ensure plans exist for everything that the given monster can do. This
# is generally done by getting the plan with get_plan, then validating
# the result; this is because get_plan ensures that the plan exists.
sub planspawn {
    my $self = shift;
    my $ai = TAEB->ai;
    my $monster = $self->monster;
    # There's not a lot we can sanely do with monsters other than try to
    # kill them, because monster objects don't persist; if we want to come
    # back and (say) buy protection, we should look for something permanent
    # like an altar.
    #
    # Unicorns and gems?  Taming monsters that aren't in the way?  Nurse
    # dancing?  Nymph curse removal?  Pudding farming?
    $ai->get_plan('Kill',$monster)->validate;
}

sub invalidate {shift->validity(0);}

use constant description => 'Doing something with a monster';
use constant references => ['Kill'];

__PACKAGE__->meta->make_immutable;
no Moose;

1;
