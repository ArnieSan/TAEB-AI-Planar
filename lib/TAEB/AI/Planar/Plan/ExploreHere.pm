#!/usr/bin/env perl
package TAEB::AI::Planar::Plan::ExploreHere;
use TAEB::OO;
use Moose;
use TAEB::Util qw/vi2delta/;
extends 'TAEB::AI::Planar::Plan';

sub spread_desirability {
    my $self = shift;
    my $level = TAEB->current_level;
    $self->depends(1,'ExploreLevel',$level);
}

use constant description => 'Exploring the current level';
use constant references => ['ExploreLevel'];

__PACKAGE__->meta->make_immutable;
no Moose;

1;
