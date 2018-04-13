#!/usr/bin/perl

package RAF;

sub preprocessing
{
	
}

# function that gets called by a single cluster job for each data point
sub run
{
  # Path to the ref alignment file
  my $refFile = shift;
  
  # path to the raw file 
  my $rawFile = $refFile;
  $rawFile =~ s/\.ref\./\.raw\./;
  
  my $parameterSet = shift;
  
  my $qm = shift;
  
  my $dir = shift;
  
  my $jobPrivatedir = $dir; 
  
  
  #~ my $RAFcall = "/usr/local/contrafold/2008-08/bin/raf predict $rawFile";
  my $RAFcall = "/home/niklas/Uni/Hiwi/ParameterOptimizationProject/raf/raf predict $rawFile";

  print $RAFcall . "\n";
  
  # move into the jobs private dir
  chdir($jobPrivatedir);
  
  # setup contrasfold
  system("setup contraf0808");
  
  my $out = `$RAFcall 2>&1`;
  print $out;

  ## Parse the RAF output
  my @out = split /\n/, $out;
  
  
  my $position = 0;
  my @resultAlignment;
  #my $resultCounter = 0;
  
  # parse sequences until consensus struct is reached
  for(my $i=0; $i < scalar(@out); $i++) {
	if($out[$i] =~ /^>(.+)/) {
		last if ($out[$i] =~ /^>consensus/); # abort if consensus is found
		my $newAlignment = {"id" => $1,
							"sequence" => $out[$i+1]};
		chomp $newAlignment->{id};
		chomp $newAlignment->{sequence};

		push(@resultAlignment, $newAlignment);
	}
  }
  
    
  # print clustalw file
  open(my $clustalW, ">temp.clustalw");
  print $clustalW "CLUSTAL W (1.83) multiple sequence alignment\n\n";
  foreach my $row (@resultAlignment) {
	  print $clustalW $row->{id} . "\t" . $row->{sequence} . "\n";
  }
  close($clustalW);
  
  # call alifold
  my $alifoldOut = `RNAalifold -r temp.clustalw`;
  print $alifoldOut;
  @out = split /\n/, $alifoldOut;
  
  my $consensusStruct = $out[1];
  #remove everything after the first space
  $consensusStruct =~ s/\s.*//;
  
  print $consensusStruct;
  
  my $result = { "name" =>  $locarnaCall,
                 "elements" => []};
                 
  my $firstSequence = {"id" => $data->{"elements"}->[0]->{"id"},
                       "sequence" => $data->{"elements"}->[0]->{"sequence"},
                       "sequenceWithGaps" => $resultOne};
  my $secondSequence = {"id" => $data->{"elements"}->[1]->{"id"},
                         "sequence" => $data->{"elements"}->[1]->{"sequence"},
                         "sequenceWithGaps" => $resultTwo};
                         
  push(@{$result->{"elements"}}, $firstSequence);
  push(@{$result->{"elements"}}, $secondSequence);
  
  my $end = time;

  # Evaluation
  



  #~ $qm->{"time"} =  $totalTime - $bppTime;
  #~ $qm->{"score"} =  $score;
  #~ $qm->{"name"} = $locarnaCall;
  #~ 
  return $result;
}

sub postprocessing
{
  
}
# objectiveFunction($results, $baseDir, $parameterSet, $logFileHandle)
sub objectiveFunction
{
  my $results = shift;
  my $baseDir = shift;
  my $params = shift;
  my $logFile = shift;
  
  my $hits = 0;
  my $runs = scalar(keys(%{$results}));
  
  while(my ($key,$value) = each(%{$results}))
  {
    $hits += $value->{"hitRate"};
    print $logFile $value->{"hitRate"} . " " . $value->{"name"} . "\n";
  }
  my $average = ($runs==0)?0:$hits/$runs;
  print $logFile "avg SPS: " . $average . "\n";
  return $average;
}

# Private subs

sub getAlignmentEdges
{
  my $alignment = shift;
    
  # first sequence with gaps
  my @gappedA = split //, $alignment->{"elements"}->[0]->{"sequenceWithGaps"};
  # second sequence with gaps
  my @gappedB = split //, $alignment->{"elements"}->[1]->{"sequenceWithGaps"};
  # sequence without gaps
  my @seq = split //, $alignment->{"elements"}->[0]->{"sequence"};
  
  # a counter pair, pointing to the current position in both sequences
  my @currentPos = (0 , 0);
  
  for(my $i = 0; $i < scalar(@gappedA);$i++)
  {
    # case 1: match / mismatch
    if ($gappedA[$i] ne "-" and $gappedB[$i] ne "-") {
        # set the alignment edge
        $seq[$currentPos[0]] = $currentPos[1];
        
        # count up the pointers
        $currentPos[0]++;
        $currentPos[1]++;
        next;
    }
    # case 2: gap in first sequence
    if ($gappedA[$i] eq "-" and $gappedB[$i] ne "-") {
        # count up second counter
        $currentPos[1]++;
        next;
    }
    # case 3: gap in second sequence
    if ($gappedA[$i] ne "-" and $gappedB[$i] eq "-") {
        $seq[$currentPos[0]] = "-1";
        
        # count up first counter
        $currentPos[0]++;
        next;
    }
    # this should never be reached as that would mean - and - are matched
    print "two gaps matched!!!!!";
  }
  
  return \@seq;
}


1;
