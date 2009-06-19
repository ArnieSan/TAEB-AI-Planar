package TAEB::AI::Planar::Meta::Trait::DontFreeze;
use Moose::Role;

no Moose::Role;

package Moose::Meta::Attribute::Custom::Trait::TAEB::DontFreeze;
sub register_implementation { 'TAEB::AI::Planar::Meta::Trait::DontFreeze' }

1;
