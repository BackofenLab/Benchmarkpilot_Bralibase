#!/usr/bin/perl

package LocarnaN;

sub preprocessing
{
  my $dir = shift; # the path of the temporary directory
  my $data = shift;
  
  chdir($dir);
  mkdir("inputFasta");
  chdir("inputFasta");
  foreach my $dataElement (@{$data})
  {
    my $filename = $dataElement->{"name"};
    $filename =~ s/\//-/g;
    $filename = $dir . "inputFasta/" . $filename;

    # Write each sequence in a separate fasta file
    foreach my $sequence (@{$dataElement->{"elements"}})
    {
      my $id = $sequence->{"id"};
      
      my $completeFilename = $filename . $id . ".fasta";
		
      open(my $fastaFile, ">$completeFilename");
      
      print $fastaFile ">$id\n";
      print $fastaFile uc($sequence->{sequence}) . "\n";
      
      close($fastaFile);
    }
    
  }
}

# function that gets called by a single cluster job for each data point
sub run
{
  my $data = shift;
  
  my $parameterSet = shift;
  
  my $qm = shift;
  
  my $dir = shift;
  
  my $start = time;
  
  # parse the parameters
  my $gapcost = $parameterSet->{"gapcost"};
  
  # indel cost are actually negative
  my $i = $gapcost * -1;
  
  my $a = $data->{"elements"}->[0]->{"sequence"};
  my $b = $data->{"elements"}->[1]->{"sequence"};
  
  
  my $dataID = $data->{"name"};
  $dataID =~ s/\//-/g;
  my $inFile1 = $dir . "inputFasta/" . $dataID . $data->{"elements"}->[0]->{"id"} . ".fasta";
  my $inFile2 = $dir . "inputFasta/" . $dataID . $data->{"elements"}->[1]->{"id"} . ".fasta";
  
  my $locarnaCall = "/home/meinzern/tools/locarna-1.7.2.6/bin/locarna_n -w 10000 --indel $i -p0.001 --prob_unpaired_in_loop_threshold=0.00001 --prob_basepair_in_loop_threshold=0.00001 $inFile1 $inFile2";
  #~ my $locarnaCall = "/home/meinzern/tools/locarna-1.7.2.6/bin/locarna -w 10000 --indel $i -p0.001 --indel-opening=0 $inFile1 $inFile2";
  print $locarnaCall . "\n";
  
  my $out = `$locarnaCall 2>&1`;
  print $out;

  ## Parse the locarna output
  my @out = split /\n/, $out;
  
  # find the first line that starts with "Score"
  # this is the start of the regular output, there are possible warnings before that
  my $offset = 0;
  for(my $i = 0; $i < scalar(@out); $i++){
	 last if ($out[$i] =~ /^Score/);
	 $offset++;
  }  
  # extract the lines of interests, i.e.:
  #   line 0: The score
  #   line 3: the first line of the alignment
  #   line 4: the second line of the alignment
  #   line 10: the time needed for bpp calculation
  #   line 11: the time needed in total
  my $score = $out[0+$offset];
  my $resultOne = $out[3+$offset];
  my $resultTwo = $out[4+$offset];
  my $bppTime = $out[10+$offset];
  my $totalTime = $out[11+$offset];
  
  # reduce alignment lines to only the alignment (remove descriptor and spaces)
  my @temp = split /\s+/, $resultOne;
  $resultOne = $temp[1];
  @temp = split /\s+/, $resultTwo;
  $resultTwo = $temp[1];
  # isolate score value
  @temp = split /\s+/, $score;
  $score = $temp[1];
  
  # isolate the time values
  @temp = split /\s+/, $bppTime;
  $bppTime = $temp[2];
  $bppTime =~ s/s//;
  @temp = split /\s+/, $totalTime;
  $totalTime = $temp[2];
  $totalTime =~ s/s//;
    
  # replace non standard gap symbols
  $resultOne =~ s/[~_]/-/g;
  $resultTwo =~ s/[~_]/-/g;
    
  #print $resultOne . "\n" . $resultTwo . "\n$score\n";
  
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
  
  my $refE = getAlignmentEdges($data);
  my $resE = getAlignmentEdges($result);
  
  # total = alignment edges in reference alignment
  my $total = scalar(@{$refE});
  # actually = alignment edges in calculated alignment
  my $actually = 0;
  
  for(my $i = 0; $i < $total; $i++)
  {
    if($refE->[$i] eq $resE->[$i] && $refE->[$i] != -1)
    {
      $actually++;
    }
  }
  
  $qm->{"hitRate"} = $actually/$total;


  $qm->{"time"} =  $totalTime - $bppTime;
  $qm->{"score"} =  $score;
  $qm->{"name"} = $locarnaCall;
  
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
