#!/usr/bin/env perl
package TAEB::AI::Planar::Plan::CharacterMeta;
use TAEB::OO;
extends 'TAEB::AI::Planar::Plan';

# A plan that does nothing but create other plans, as appropriate to
# the status of the character.

sub planspawn {
    my $self = shift;
    my $ai = TAEB->ai;
    if (TAEB->is_lycanthropic) {
        $ai->get_plan('Wolfsbane')->validate;
    }
    if (TAEB->nutrition <= 49) {
        $ai->get_plan('PrayForFood')->validate;
    }
    if (TAEB->hp < TAEB->maxhp) {
	$ai->get_plan('Rest')->validate;
    }
}

sub invalidate {shift->validity(0);}

use constant description => 'Improving my character';
use constant references => ['Wolfsbane','PrayForFood','Rest'];

__PACKAGE__->meta->make_immutable;
no Moose;

1;
