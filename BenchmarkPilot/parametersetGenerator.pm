package parametersetGenerator;

use strict;
use warnings;

use feature "switch";

sub new
{
  my $class = shift;
  my $self = {};
  
  my $filename = shift;
  
  
  if(!defined $filename)
  {
    die("ParameterFile not given!\n");
  }
  if(!-e $filename)
  {
    die("ParameterFile $filename does not exist!\n");
  }
  
  $self->{"parameters"} = [];
  $self->{"completed"} = 0;
  
  open(FILE, $filename);
  
  my $linecounter = -1;
  while(my $line = <FILE>)
  {
    my $linecounter++;
    next if ($line =~ /^#/ || length($line) == 0);
    chomp $line;
    my @line = split/\t/, $line;
    if(scalar(@line) == 2)
    {
      given($line[0])
      {
        when("INTERVAL")
        {
          push(@{$self->{"parameters"}}, newIntervalParameter($line[1]));
        }
        when("SWITCH")
        {
          push(@{$self->{"parameters"}}, newBoolParameter($line[1]));
        }
        default
        {
          die("Invalid parameter File! Unknown type!\n");
        }
     }
    }else
    {
      die("Invalid parameter File! More than two columns in line $linecounter\n");
    }
  }
  
  $self->{"active"} = 0;
  
  bless $self, $class;
  
  return $self;
}

sub newIntervalParameter
{
  my $input = shift;
  
  die("parametersetGenerator::newIntervalParameter: no input given!\n") if(!defined $input);
  
  my @specs = split / /, $input;
  
  if(scalar(@specs) < 2 or scalar(@specs) > 3)
  {
    die("parametersetGenerator::newIntervalParameter: invalid input: $input\n");
  }
  
  my $interval = $specs[1];
  my $stepsize = 1;
  $interval =~ s/\[|\]//g;
  my ($low,$high) = split/,/, $interval;
  
  # Stepsize given?
  my $operator = "+";

  if($high =~ /\|/)
  {
    ($high, $stepsize) = split /\|/, $high;
    if(($stepsize =~ /^(\d+\.?\d*)(\*?)$/))
    {
        $stepsize = $1;
        if ($stepsize == 0) {
            die("parametersetGenerator::newIntervalParameter: Stepsize is 0!\n");
        }
        if (length($2) > 0) {
            if ($2 eq "*") {
                $operator = "*";
            } else {
                die("parametersetGenerator::newIntervalParameter: unknown operator '$2' only '*' is supported!\n");
            }
        }
    } else {
        die("parametersetGenerator::newIntervalParameter: Stepsize is not a number!\n");
    }
  }
  
  my $output = {};
  
  $output->{"name"} = $specs[0];
  $output->{"prettyName"} = $specs[0];
  $output->{"low"} = $low;
  $output->{"high"} = $high;
  $output->{"current"} = $low;
  $output->{"type"} = "interval";
  $output->{"stepsize"} = $stepsize;
  $output->{"operator"} = $operator;
  if(defined $specs[2] )
  {
    $output->{"current"} = $specs[2];
  }
  $output->{"best"} = $output->{"current"};
  
  if($output->{"current"} < $output->{"low"} || $output->{"current"} > $output->{"high"})
  {
    die("\nparametersetGenerator::newIntervalParameter: Starting value not in interval!" .  $output->{"name"} ." \n");
  }
  
  # Check if a prettyName for output was given
  if($specs[0] =~ m/\|/)
  {
	  my @splitted = split /\|/, $specs[0];
	  
	  $output->{"name"} = $splitted[0];
	  $output->{"prettyName"} = $splitted[1];
  }
  
  return $output;
  
}


sub newBoolParameter
{
  my $input = shift;
  
  die("parametersetGenerator::newBoolParameter: no input given!\n") if(!defined $input);
  
  my @specs = split / /, $input;
  
  if(scalar(@specs) != 1 && scalar(@specs) != 2)
  {
    die("parametersetGenerator::newBoolParameter: invalid input: $input\n");
  }
  
  my $output = {};
  
  $output->{"name"} = $specs[0];
  $output->{"prettyName"} = $specs[0];
  $output->{"current"} = 0;
  $output->{"type"} = "bool";
  
  if(defined $specs[1])
  {
    $output->{"current"} = $specs[1];
  }
  
  if($specs[0] =~ m/\|/)
  {
	  my @splitted = split /\|/, $specs[0];
	  
	  $output->{"name"} = $splitted[0];
	  $output->{"prettyName"} = $splitted[1];
  }
  
  $output->{"best"} = $output->{"current"};

  return $output;
}

# returns the next parameterset or undef if all have been returned
sub next
{
  my $self = shift;
  
  my $numOfParameters = scalar(@{$self->{"parameters"}});
  
  if($self->{"completed"})
  {
    return undef;
  }
  
  my $changeMade = 0;
  
  my $output = {};
  for(my $i = 0; $i < $numOfParameters; $i++)
  {
    if($i == $self->{"active"})
    {
      $output->{$self->{"parameters"}->[$i]->{"name"}} = $self->{"parameters"}->[$i]->{"current"};
      $output->{"!ACTIVE-VALUE"} = $self->{"parameters"}->[$i]->{"current"};
      $output->{"!ACTIVE-NAME"} = $self->{"parameters"}->[$i]->{"name"};
      $self->{"lastChanged"} = [$i,$self->{"parameters"}->[$i]->{"current"}];
    }else
    {
      $output->{$self->{"parameters"}->[$i]->{"name"}} = $self->{"parameters"}->[$i]->{"best"};
    }
  }

  $output->{"ACTIVE"} = $self->{"active"};

  
  
  for(my $i = 0; $i < $numOfParameters; $i++)
  {
    if($i == $self->{"active"})
    {
      given($self->{"parameters"}->[$i]->{"type"})
      {
        # Interval parameter
        when("interval")
        {
          # If next step would be higher as the set maximum, move to next parameter
          my $nextValue = 0;
          if ($self->{"parameters"}->[$i]->{"operator"} eq "+") {
             $nextValue = $self->{"parameters"}->[$i]->{"current"} + $self->{"parameters"}->[$i]->{"stepsize"};
          } elsif ($self->{"parameters"}->[$i]->{"operator"} eq "*") {
             $nextValue = $self->{"parameters"}->[$i]->{"current"} * $self->{"parameters"}->[$i]->{"stepsize"};
          }
          if($nextValue > $self->{"parameters"}->[$i]->{"high"})
          {
            $self->{"active"}++;
            if($self->{"active"} >= $numOfParameters)
            {
              $self->{"active"}--;
              $self->{"completed"} = 1;
            }else
            # set the next parameter to the lowest possible
            {
              given($self->{"parameters"}->[$self->{"active"}]->{"type"})
              {
                when("interval")
                {
                  $self->{"parameters"}->[$self->{"active"}]->{"current"} = $self->{"parameters"}->[$self->{"active"}]->{"low"};
                }
                when("bool")
                {
                  $self->{"parameters"}->[$self->{"active"}]->{"current"} = 0;
                }
                default
                {
                  die("unknown parameter type");
                }
              }
            }
          }else
          {
            $self->{"parameters"}->[$i]->{"current"} = $nextValue;
          }
          last;
        }
        # switch parameter
        when("bool")
        {
          if($self->{"parameters"}->[$i]->{"current"} == 1)
          {
            $self->{"active"}++;
            if($self->{"active"} >= $numOfParameters)
            {
              $self->{"active"}--;
              $self->{"completed"} = 1;
            }
          }else
          {
            $self->{"parameters"}->[$i]->{"current"} = 1;
          }
          last;
        }
        default
        {
          die("unknown parameter type");
        }
      }
    }
  }
  return $output;
}

sub reportBest
{
  my $self = shift;
  
  my $value = shift;
  if(!defined $value)
  {
    die("parametersetGenerator::reportBest: No value given!\n");
  }
  #print "reporting " . $self->{"lastChange"} . " at " . 
  $self->{"parameters"}->[$self->{"lastChanged"}->[0]]->{"best"} = $self->{"lastChanged"}->[1];
  $self->{"bestValue"} = $value;
}

sub getBestSet
{
  my $self = shift;
  
  my $numOfParameters = scalar(@{$self->{"parameters"}});

  my $output = {};
  for(my $i = 0; $i < $numOfParameters; $i++)
  {
    $output->{$self->{"parameters"}->[$i]->{"name"}} = $self->{"parameters"}->[$i]->{"best"};
  }
  
  $output->{"VALUE"} = $self->{"bestValue"};
  return $output;
}

sub parameterSetToString
{
  my $ps = shift;
  
  if(!defined $ps)
  {
    die("parametersetGenerator::parameterSetToString: No parameter set given!\n");
  }
  
  my $output = "";
  
  foreach my $key (sort(keys(%{$ps})))
  {
    next if($key eq "ACTIVE");
    next if($key =~ m/^!/);
    $output .= $key . "-" . $ps->{$key} . "_";
  }
  
  return $output;
}

# Calls gnuplot and plots data from given file
sub plotData
{
  my $self = shift;
  my $file = shift;
  my $outputFile = shift;
  my $paramNumber = shift;
  my $dataSet = shift;
  my $tool = shift;
  
  my $paramName = $self->{"parameters"}->[$paramNumber]->{"prettyName"};
  $outputFile .= $paramName;
  open (GNUPLOT, "|gnuplot > /dev/null 2>&1");
print GNUPLOT <<EOPLOT;
set term png small xFFFFFF
set output "$outputFile.png"
set size 1 ,1
set nokey
set data style line
set xlabel "value of parameter: $paramName"
set ylabel "average SPS"
set title "Optimization run for parameter $paramName ($paramNumber), tool: $tool, data set: $dataSet"
set grid xtics ytics
set pointsize 2
plot "$file" using 1:2 w points 10
EOPLOT
close(GNUPLOT);

unlink($file);
}


# Returns how many parameter sets are going to be tested
sub numOfSets
{
  use POSIX;
  
  my $self = shift;
  my $result = 0;
  foreach my $param (@{$self->{"parameters"}})
  {
    if($param->{"type"} eq "bool")
    {
      $result += 2;
    }
    if($param->{"type"} eq "interval")
    {
      my $range = $param->{"high"} - $param->{"low"} + 1;
      $result +=  floor($range/$param->{"stepsize"});
      
    }
  }
  return $result;
}


1;
