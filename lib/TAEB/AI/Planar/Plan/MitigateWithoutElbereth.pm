#!/usr/bin/env perl
package TAEB::AI::Planar::Plan::MitigateWithoutElbereth;
use TAEB::OO;
use Moose;
extends 'TAEB::AI::Planar::Plan';

# We take a monster as argument.
has (monster => (
    isa     => 'Maybe[TAEB::World::Monster]',
    is  => 'rw',
    default => undef,
));
sub set_arg {
    my $self = shift;
    $self->monster(shift);
}

# This is a meta-meta-plan.  There is a troublesome monster, so spread
# desire to ways of making it less troublesome.
sub spread_desirability {
    my $self = shift;
    $self->depends(1,"Eliminate",$self->monster);
    # TODO: don't Elbereth as a result of this
    $self->depends(0.5,"CombatFallback");
}

# This requires a continuous stream of validity from the threat map
sub invalidate {shift->validity(0);}

use constant description => "Mitigating a threatening Elbereth-ignoring monster";
use constant references => ['Eliminate', 'CombatFallback'];

__PACKAGE__->meta->make_immutable;
no Moose;

1;
