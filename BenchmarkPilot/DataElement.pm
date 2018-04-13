package DataElement;
use strict;
use warnings;

=head1 NAME

DataElement

=head1 SYNOPSIS

=head1 AUTHOR: 

Niklas Meinzer <meinzern@informatik.uni-freiburg.de>


=cut


sub new
{
	my $class = shift;
	my $self = {};
	
	bless $self, $class;
	
	$self->intitialize();
}


sub initialize
{
	my $self = shift;
	
	$self->{"id"} = "";
	$self->{"data"} = {};
	
}

1;
