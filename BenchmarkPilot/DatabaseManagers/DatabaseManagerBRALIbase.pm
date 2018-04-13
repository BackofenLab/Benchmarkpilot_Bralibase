package DatabaseManagerBRALIbase;
use strict;
use warnings;
use BPUtilities;
use Storable qw(dclone);


=head1 NAME

DatabaseManagerBRALIbase - A module to access BRALIbase at the uni freiburg bioinformatics lab

=head1 SYNOPSIS

=head1 AUTHOR: 

Niklas Meinzer <meinzern@informatik.uni-freiburg.de>


=cut
use base "DatabaseManager";

# use constant BRALIDIR => "/scratch/db/BRALIBASE";
# use constant BRALIDIR => "/scratch/1/muellert/TeamProjekt/Output/Test_BraliBase_Results"; 
# use constant BRALIDIR => "/scratch/1/muellert/TeamProjekt/Output/BraliBaseOutput_70_NegativTestSet"; 
# use constant BRALIDIR => "/scratch/1/muellert/TeamProjekt/BRALIBASE_Input"; 
# use constant BRALIDIR => "/scratch/1/muellert/TeamProjekt/Output/Updated_BralibaseOutput_20"; 
# use constant BRALIDIR => "/scratch/1/muellert/TeamProjekt/Output/Updated_BralibaseOutput_70"; 
# use constant BRALIDIR => "/scratch/1/muellert/TeamProjekt/Output/Updated_BralibaseOutput_NegativeTestSet_20"; 

use constant BRALIDIR => "/scratch/1/muellert/TeamProjekt/Output/TestPositionCon20"; 
# use constant BRALIDIR => "/scratch/1/muellert/TeamProjekt/Output/ModifiedBralibase-Context20"; 

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
  
  my $db = shift;
  
  if(defined $db)
  {
    $self->{"dbdir"} = $db;
  }
  else
  {
    $self->{"dbdir"} = BRALIDIR;
  }
  
  $self->{"property"} = 1;
  
  $self->SUPER::initialize();
}

sub getElements
{
  my $self = shift;
  
  if(!-e $self->{"dbdir"} || !-d $self->{"dbdir"})
  {
    die(BPUtilities::redString("Bralibase base directory not found! Should be at ". $self->{"dbdir"}."\n"));
  }
  
  my $path = shift;
  
  my $dataset = {"id" => $path,
                "data" => []};  
  

  die(BPUtilities::redString("DatabaseManagerBRALIbase::getElement: No Elementpath defined!\n"))
        if(!defined $path);
  
  $path = $self->{"dbdir"} . "/" . $path;

  # exit with error if the path does not exist
  if (!-e $path) {
    die(BPUtilities::redString("\n$path is not a valid BRALIbase dataset identifier!"));
  }
  
  # enter recursion
  $self->getElementsRecursive($path, $dataset->{"data"});
  
  print "final size: " . scalar(@{$dataset->{"data"}}) ."\n";
  
  return $dataset;
  
}

sub getElementsRecursive
{
  my $self = shift;
  
  my $path = shift;
  
  print "current path: $path\n";
  my $dataList = shift;
  
  # collect all data within the directory

  opendir(DIR, $path);
  my  @files = readdir(DIR);
  closedir(DIR);
  
  foreach my $file (@files)
  {

    if(-d $path . "/" . $file)
    {
      next if($file =~ /\./);
      $self->getElementsRecursive($path . "/" . $file, $dataList);
      next;
    }
    if($file =~ /.ref.fa/)
    {

      push(@{$dataList}, $self->parseBraliBaseFile($path . "/" . $file));
    }
  }
}

sub parseBraliBaseFile
{
  my $self = shift;
  
  my $filename = shift;
  
  if(!-e $filename)
  {
    die("DatabaseManagerBRALIbase::parseBraliBaseFile: No filename given or file does not exist!\n");
  }
  
  my $data = {"name" => "TODO",
              "elements" => []};
              
  $data->{"name"} = $filename;
  my $dir = $self->{"dbdir"};
  $data->{"name"} =~ s/^($dir)\///;
  $data->{"name"} =~ s/.ref.fa$//;
  
  my $entry = {};
  
  open(FILE, $filename);
  
  while(my $line = <FILE>)
  {
    chomp $line;
    if($line =~ /^>/)
    {
      if(defined $entry->{"id"})
      {
        $entry->{"sequence"} = $entry->{"sequenceWithGaps"};
        $entry->{"sequence"} =~ s/-//g;
        my $newEntry = dclone($entry);
        push(@{$data->{"elements"}}, $newEntry);
      }
      $line =~ s/>//g;
      $line =~ s/\s*//g;
      $entry = {};
      $entry->{"id"} = $line;
      $entry->{"sequenceWithGaps"} = "";
    }else
    {
      $entry->{"sequenceWithGaps"} .= $line;
    }
  }
  close(FILE);
  if(defined $entry->{"id"})
  {
    $entry->{"sequence"} = $entry->{"sequenceWithGaps"};
    $entry->{"sequence"} =~ s/-//g;
    my $newEntry = dclone($entry);
    push(@{$data->{"elements"}}, $newEntry);
  }  
  return $data;
}
1;
