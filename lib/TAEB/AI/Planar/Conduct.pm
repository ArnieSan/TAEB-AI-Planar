#!/usr/bin/env perl
package TAEB::AI::Planar::Conduct;
use TAEB::OO;
extends 'TAEB::AI::Planar::Resource';

# Conducts in Planar are handled as a subtype of resource.  They
# represent the value of keeping a conduct and are either worthless
# or infinitely valuable.

has _keeping => (
    isa     => 'Bool',
    is      => 'ro',
    default => sub {
        (blessed $_[0]) =~ /.*::(.*)/;
        return TAEB->config->get_ai_config->{lc $1} // 0;
    }
);

sub amount { (shift->_keeping) ? 0 : 1e7 }

has _value => (
    isa     => 'Num',
    is      => 'rw',
    default => sub { (shift->_keeping) ? 1e7 : 1e-7 }
);

sub scarcity {
    return 1;
}

sub want_to_spend { }

__PACKAGE__->meta->make_immutable;
no Moose;

1;
