package DatabaseManager;
use strict;
use warnings;

=head1 NAME

DatabaseManager - A module to access databases at the uni freiburg bioinformatics lab

=head1 SYNOPSIS

=head1 AUTHOR: 

Niklas Meinzer <meinzern@informatik.uni-freiburg.de>


=cut


#######################################################################
# Creates a new DatabaseManager object
# INPUT: todo
# OUTPUT: todo
#######################################################################
sub new
{
  my $class = shift;
  my $self = {};
  
  bless $self, $class;
  
  $self->initialize();
  
  return $self;
}

sub initialize
{
  my $self = shift;
  
  $self->{"superProperty"} = 1;
}

# This method must be overridden by the instanciations
# it must return a hash reference
# $ref -> {id -> "id or name of the dataset"
#          elements -> array of hashref -> id "id of data point"
#                                       -> data point as
#                                          tool in question expects them           
sub getElements
  {
      die "This method must be overridden by a subclass of __PACKAGE__";
  }

1;
