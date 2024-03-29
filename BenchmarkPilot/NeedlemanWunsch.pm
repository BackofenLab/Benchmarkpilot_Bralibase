#!/usr/bin/perl

package NeedlemanWunsch;

sub getQualityMeasures
{
  return { "time" => "avg",
           "coolness" => "acc",
           "maxTime" => "max",
           "minCoolness" => "min"};
}

# This function will be called *once* for the whole benchmark run.
# You can do all your general preprocessing here (like generating
# dotPlots) it will be wrapped in a cluser job and executed via SGE.
# (for this example we don't need any preprocessing so we do nothing
# here and can also pass the --noPreprocessing flag to benchmarkPilot
# to avoid generating and waiting for a cluster job that does nothing
sub preprocessing
{
  
}

# This function executes one call of the benchmarked program with 
# one data point and one parameter set.
# The parameters are:
#   - $data: A hash reference to the test data with the elements
#            "name" and "elements". Elements is an array reference
#            to an array that holds all required elements of your
#            test point. In this example two sequences that should
#            be aligned.
#   - $parameterSet:
#            A set of parameters, with a values auto generated with the
#            information take from your parameter file. For each 
#            parameter you specified you get one hash key corresponding
#            to the value of that parameter for this run.
#   - $qm:
#             The quality measures
sub run
{
  my $data = shift;
  
  my $parameterSet = shift;
  
  my $qm = shift;
  
  my $start = time;
  
  my $d = $parameterSet->{"d"};
  my $i = $parameterSet->{"i"};
  my $m = $parameterSet->{"m"};
  
  my $a = $data->{"elements"}->[0]->{"sequence"};
  my $b = $data->{"elements"}->[1]->{"sequence"};

  my $call = "./NeedlemanWunsch.pl -a $a -b $b -m $m -d $d -i $i";
  #~ print $call . "\n";
  my $out = `$call`;
  my @out = split /\n/, $out;
  #~ print $out[0] . "\n" . $out[1] . "\n\n";
  
  my $result = { "name" => "ToolResult",
                 "elements" => []};
                 
  my $firstSequence = {"id" => $data->{"elements"}->[0]->{"id"},
                       "sequence" => $data->{"elements"}->[0]->{"sequence"},
                       "sequenceWithGaps" => $out[0]};
  my $secondSequence = {"id" => $data->{"elements"}->[1]->{"id"},
                         "sequence" => $data->{"elements"}->[1]->{"sequence"},
                         "sequenceWithGaps" => $out[1]};
                         
  push(@{$result->{"elements"}}, $firstSequence);
  push(@{$result->{"elements"}}, $secondSequence);
  
  my $end = time;
  
  my $temp = rand;

  $qm->{"coolness"} = $temp;
  $qm->{"minCoolness"} = $temp;
  
  my $refE = getAlignmentEdges($data);
  my $resE = getAlignmentEdges($result);
  
  my $total = scalar(@{$refE});
  my $actually = 0;
  
  for(my $i = 0; $i < $total; $i++)
  {
    if($refE->[$i] eq $resE->[$i] && $refE->[$i] != -1)
    {
      $actually++;
    }
  }
  $qm->{"hitRate"} = ($total==0)?0:$actually/$total;


  $qm->{"time"} =  ($end -$start);
  $qm->{"maxTime"} =  ($end -$start);
  
  return $result;
}
# This function will be called *once* after all runs are completed
# You can do all necessary cleanups here
sub postprocessing
{
  print "I am doing postprocessing!\n";
}

## objectiveFunction($results, $baseDir, $parameterSet, $logFileHandle, $failedData, [$auxFileHandle])
## auxfilehandle is only passed if --auxOutput was given to benchmarkPilot
#
# This function is called after all data points have been tested on one
# parameter set. Evaluate the results and return a result that indicates
# the quality of the parameter set. BenchmarkPilot will try to maximize
# this value.
# You get:
#     - $results: A hash reference to a hash that maps from the ID of
#                 the datapoint to a hash reference of the qm hash
#                 that you generated in the run function.
#     - $basDir:  The directory you specified as this runs base directory
#                 in BenchmarkPilot
#     - $params:  The parameters this tool uses (i.e. those you specified
#                 in the parameter file)
#     - $logFile: An open filehandle to the log file generated by benchmark
#                 pilot. You can just print to it without opening it
#     - $failedData:
#                 An array reference to an array with the id's of all 
#                 datapoints for which the run failed (i.e. exceeded the
#                 timout)
#     - $auxFile:
#                 An open filehandle to the auxilliary log file in which
#                 *only this function* prints stuff. This parameter will
#                 only be present if you passed the --auxOutput parameter
#                 in benchmarkPilot. (this functionality was added I case
#                 you want to create a specially formated result file)
#                
sub objectiveFunction
{
  my $results = shift;
  my $baseDir = shift;
  my $params = shift;
  my $logFile = shift;
  my $failedData = shift;
  my $auxFile = shift;
  
  my $hits = 0;
  my $runs = scalar(keys(%{$results}));
  
  while(my ($key,$value) = each(%{$results}))
  {
    $hits += $value->{"hitRate"};
  }
  
  return ($runs==0)?0:$hits/$runs;
}

# Private subs

sub getAlignmentEdges
{
  my $alignment = shift;
  
  my @gappedA = split //, $alignment->{"elements"}->[0]->{"sequenceWithGaps"};
  my @gappedB = split //, $alignment->{"elements"}->[1]->{"sequenceWithGaps"};
  my @seq = split //, $alignment->{"elements"}->[0]->{"sequence"};
  
  my $counter = 0;
  
  for(my $i = 0; $i < scalar(@gappedA);$i++)
  {
    if($gappedA[$i] ne "-")
    {
      if($gappedB[$i] ne "-")
      {
        $seq[$counter] = $i;
      }else
      {
        $seq[$counter] = -1;
      }
      $counter++;
    }
  }
  
  return \@seq;
}


1;
