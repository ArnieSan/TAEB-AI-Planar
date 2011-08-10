#!/usr/bin/env perl
package TAEB::AI::Planar::Plan::Wolfsbane;
use TAEB::OO;
use Moose;
extends 'TAEB::AI::Planar::Plan::Strategic';

sub aim_tile {
    my $self = shift;
    return unless TAEB->is_lycanthropic;
    return unless TAEB::Action::Pray->is_advisable;
    $_->maybe('is_lycanthrope') and return for TAEB->current_level->monsters;
    return TAEB->current_tile;
}

sub has_reach_action { 1 }
sub reach_action {
    my $self = shift;
    return TAEB::Action->new_action('pray');
}

# Resource conversion: lose a prayer, gain purity
sub gain_resource_conversion_desire {
    my $self = shift;
    my $ai   = TAEB->ai;
    # Bump our own desirability.
    $ai->add_capped_desire($self, $ai->resources->{'Purity'}->value);
}

sub calculate_extra_risk {
    return 0; # can't be attacked during prayer...
}

# This plan needs a continuous stream of validity from our senses.
sub invalidate {shift->validity(0);}

use constant description => 'Curing lycanthropy';

__PACKAGE__->meta->make_immutable;
no Moose;

1;
