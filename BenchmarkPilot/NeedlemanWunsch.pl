#!/usr/bin/perl

use Getopt::Std;

my %options=();
getopts("a:b:d:m:i:", \%options);

my $a = $options{"a"};
my $b = $options{"b"};
my $deletion = $options{"d"};
my $match = $options{"m"};
my $mismatch = $options{"i"};

if(!defined $a || !defined $b || !defined $deletion || !defined $match || !defined $mismatch)
{
  die("invalid parameters!\n");
}

my $NW = needlemanWunsch->new($deletion, $mismatch, $match);

$NW->align($a, $b);


package needlemanWunsch;

use warnings;
use strict;

sub new 
{
  my $class = shift;
  my $self = {};
  
  
  
  $self->{"cost"} = [shift,shift,shift];
  
  bless $self, $class;
  
  return $self;
}
	
  
sub align{
  
  my $self = shift;
  
  my $a = shift;
  my $b = shift;
  
  my @A = split //,$a;
  my @B = split //,$b;
  
  my $n = length($a);
  my $m = length($b);
		
		
  my @D = ();
  for(my $i = 0; $i < $m; $i++)
  {
    push(@D, []);
  }
  
  for(my $i = 0; $i <= $n; $i++)
  {
    $D[$i][0] = $i * $self->{"cost"}->[0];
  }
  for(my $i = 0; $i <= $m; $i++)
  {
    $D[0][$i] = $i * $self->{"cost"}->[0];
  }
		
		
		# Fill Matrix
		for(my $i = 1; $i <= $n; $i++)
		{
			for(my $j = 1; $j <= $m; $j++)
			{
				# Match 
				if($A[$i-1] eq $B[$j-1])
				{
					$D[$i][$j] = min( min(
							$D[$i-1][$j-1] + $self->{"cost"}->[2], # Match 
							$D[$i][$j-1] + $self->{"cost"}->[0]) , # Gap in first sequence
							$D[$i-1][$j] + $self->{"cost"}->[0]);  # Gap in second sequence
				}else
			    # Substitution
				{
					$D[$i][$j] = min( min(
							$D[$i-1][$j-1] + $self->{"cost"}->[1],  # Substitution
							$D[$i][$j-1] + $self->{"cost"}->[0]),   # Gap in first sequence
							$D[$i-1][$j] + $self->{"cost"}->[0]);   # Gap in second sequence
				}
        
			}
		}
		
		# Calculate the traceback
		my $i = $n;
		my $j = $m;
    
    
    my $Aaligned = "";
    my $Baligned = "";
		
		while ($i != 0 || $j != 0)
		{
      #~ print "$i $j " . $A[$i-1] . " " . $B[$j-1] . "\n";
      #~ print $D[$i][$j-1] . " " .($D[$i][$j] - $self->{"cost"}->[0]) . "\n";
      #~ print $D[$i-1][$j] . " " .($D[$i][$j] - $self->{"cost"}->[0]) . "\n";
			# Case 1: Gap in sequence 1
			if ($j > 0 && $D[$i][$j-1] == ($D[$i][$j] - $self->{"cost"}->[0]))
			{
				# Introduce gap in seq1
				$Aaligned .= '-';
				$Baligned .= $B[$j-1];
				$j--;
				next;
			}
			# Case 2: Gap in sequence 2
			if($i > 0 && $D[$i-1][$j] == ($D[$i][$j] - $self->{"cost"}->[0]))
			{
				# Introduce gap in seq2
				$Aaligned .= $A[$i-1];
				$Baligned .= "-";
				$i--;
				next;
			}
			# Case 3: Substitution
			if($i > 0 && $j > 0 && $D[$i-1][$j-1] == ($D[$i][$j] - $self->{"cost"}->[1])
					&& ($A[$i-1] ne $B[$j-1]))
			{
				$Aaligned .= $A[$i-1];
				$Baligned .= $B[$j-1];
				$i--;
				$j--;
				next;
			}
			# Case 4: Match
			if($i > 0 && $j > 0 && ($D[$i-1][$j-1] == $D[$i][$j] - $self->{"cost"}->[2])
					&& ($A[$i-1] eq $B[$j-1]))
			{
				$Aaligned .= $A[$i-1];
				$Baligned .= $B[$j-1];
				$i--;
				$j--;
				next;		
			}
			die("error");
			# ERROR
		}
		# After the traceback is comnpleted, revert the output Sequences
		#Aaligned.setSequence(new StringBuffer(Aaligned.getSequence()).reverse().toString());
		#Baligned.setSequence(new StringBuffer(Baligned.getSequence()).reverse().toString());
		
		# Set the outputMessage
		#~ outputMessage += "This alignment was found using the following cost function:\n"
			#~ + "Deletion/Insertion: " + Integer.toString(cost[0]) 
			#~ + " Substitution: " + Integer.toString(cost[1])
			#~ + " Match: " + Integer.toString(cost[2])
			#~ + "\nIt's score is " + Integer.toString($D[n][m]);
		#~ 
    $Aaligned = reverse $Aaligned;
    $Baligned = reverse $Baligned;
    
    print $Aaligned . "\n";
    print $Baligned . "\n";
    print "Score: " . $D[$n][$m] . "\n";
	}

sub min
{
  my $a = shift;
  my $b = shift;
  
  if($a > $b)
  {
    return $b;
  }
  else
  {
    return $a;
  }
}
