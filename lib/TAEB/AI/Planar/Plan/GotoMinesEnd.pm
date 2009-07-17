#!/usr/bin/env perl
package TAEB::AI::Planar::Plan::GotoMinesEnd;
use TAEB::OO;
extends 'TAEB::AI::Planar::Plan';

sub spread_desirability {
    my $self = shift;

    if (!TAEB->current_level->known_branch || TAEB->current_level->branch ne 'mines') {
        $self->depends(1,"GotoMines");
    } else {
        $self->depends(1,"Descend");
    }
}

use constant description => 'Going to the Mines\' End';
use constant references => ['GotoMines','Descend'];

__PACKAGE__->meta->make_immutable;
no Moose;

1;
