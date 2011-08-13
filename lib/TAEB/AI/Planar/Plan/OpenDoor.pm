#!/usr/bin/env perl
package TAEB::AI::Planar::Plan::OpenDoor;
use TAEB::OO;
use TAEB::Util qw/delta2vi/;
use Moose;
extends 'TAEB::AI::Planar::Plan::KickDownDoor';

sub special_door_risk { 0 }

use constant door_action => 'open';
use constant chance_factor => 60;

# and otherwise it's the same as kicking down a door

use constant description => 'Opening a door';

__PACKAGE__->meta->make_immutable;
no Moose;

1;
