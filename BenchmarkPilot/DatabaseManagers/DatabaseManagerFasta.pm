package DatabaseManagerFasta;
use strict;
use warnings;
use Storable qw(dclone);


=head1 NAME

DatabaseManagerFasta - A module to access fasta files via BenchmarkPilot

=head1 SYNOPSIS

=head1 AUTHOR: 

Niklas Meinzer <meinzern@informatik.uni-freiburg.de>


=cut
use base "DatabaseManager";

sub new
{
  my $class = shift;
  my $self = {};
  bless $self, $class;
  
  $self->initialize(shift);
  
  return $self;
  
}

sub initialize
{
  my $self = shift;
  
  $self->SUPER::initialize();
}

# returns an array ref
sub getElements
{
  my $self = shift;

  my $path = shift;

  # add training / to directory, if not present
  $path .= "/" if (!($path =~ /\/$/));  
  
  if(!-e $path || !-d $path)
  {
    die("Directory " .  $path. " not found!\n");
  }

  my $dataset = {"id" => "fasta files under ". $path,
                "data" => []};

  # open the directory
  opendir(DIR, $path);
  my  @files = readdir(DIR);
  closedir(DIR);

  # iterate over all files and add them to the dataset if the have the
  # ending .fa or .fasta
  foreach my $file (@files)
  {
    if ($file =~ /.fa$/ or $file =~ /.fasta/) {
      push(@{$dataset->{data}}, { "id" => $file, "elements" => $path . $file});
    }
  }  
  print "final size: " . scalar(@{$dataset->{"data"}}) ."\n";
  
  return $dataset;
  
}
1;
