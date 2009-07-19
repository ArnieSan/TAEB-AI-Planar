#!/usr/bin/env perl
package TAEB::AI::Planar::Plan::Eliminate;
use TAEB::OO;
extends 'TAEB::AI::Planar::Plan';

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

# Does nothing but spread desire to the various methods of getting rid
# of a hostile monster. Some methods will be inappropriate in certain
# situations, but those will register as having high risk levels and
# so will be avoided unless the other options are even riskier.
#
# Note that this is if we want the monster to not be there anymore.  If
# you just want it to stop attacking you, use Mitigate instead - it has
# options like charming and scaring that aren't useful in e.g. routing
# situations.
sub spread_desirability {
    my $self = shift;
    $self->depends(1,"Kill",$self->monster);
}

sub invalidate {shift->validity(0);}

use constant description => "Eliminating a dangerous monster";
use constant references => ['Kill'];

__PACKAGE__->meta->make_immutable;
no Moose;

1;
