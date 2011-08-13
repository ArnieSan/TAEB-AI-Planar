#!/usr/bin/env perl
package TAEB::AI::Planar::Plan::Nop;
use TAEB::OO;
use TAEB::AI::Planar::TacticsMapEntry;
use Moose;
extends 'TAEB::AI::Planar::Plan::Tactical';

# A tactical plan to do nothing. Needed because we have to get the
# tactics started somehow, and to stop us coming up with a more
# expensive way to route to the square we're already on. This is
# very much a no-op plan, and serves only to be used as the tactic
# for the current square.

sub try { die 'Attempted to try to do nothing'; }
sub succeeded { return undef; }

use constant description => 'Doing nothing [this should never come up]';

__PACKAGE__->meta->make_immutable;
no Moose;

1;
