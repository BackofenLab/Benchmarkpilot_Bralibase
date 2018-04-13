#!/usr/bin/perl

package MlocarnaLocarnaN;

sub preprocessing
{

}

# function that gets called by a single cluster job for each data point
sub run
{
  # data is the name of the reference alignment file
  my $data = shift;
  
  my $refFile = $data->{path};
  # choose the raw file instead of the ref file
  my $rawFile = $refFile;
  $rawFile =~ s/\.ref\./\.raw\./;
  
  my $parameterSet = shift;
  
  my $qm = shift;
  
  my $dir = shift;
  
  # create a private subdir for this job under the dir for the whole run
  my $jobPrivateDir = $dir . "_" . $data->{"benchmarkPilotID"};
  mkdir($jobPrivateDir);
  
  # parse the parameters
  my $maxdiff = "--max-diff=" . $parameterSet->{"max-diff"};
  $maxdiff = "" if $parameterSet->{"max-diff"} == 0;
  
  # indel cost are actually negative
  #~ my $i = $gapcost * -1;
  
  my $locarnaCall = "/home/meinzern/tools/locarna-1.7.2.6/bin/mlocarna --pw-aligner /home/meinzern/tools/locarna-1.7.2.6/bin/locarna_n --pw-aligner-options \"--prob_unpaired_in_loop_threshold=0.0001 --prob_basepair_in_loop_threshold=0.0001\" -p=0.001  --LP --indel=-500 $maxdiff --tgtdir $jobPrivateDir $rawFile";
  my $timingPrefix = "/usr/bin/time -p ";
  print $locarnaCall . "\n";
  
  my $out = `$timingPrefix $locarnaCall 2>&1`;
  print $out;

  ## Parse the output
  my @out = split /\n/, $out;

  my $pairwiseBPP = 0;
  my $progBPP = 0;
  
  my $position = 0;
  # parse the bpp values
  # find "Compute pair probs"
  for(my $i = 0; $i < scalar(@out); $i++)
  {
    if($out[$i] =~ m/Compute pair probs/) {
      $position = $i;
      last;
    }
  }
  # now collection the pairwise bpp values
  for(my $i = $position; $i < scalar(@out); $i++)
  {
    if($out[$i] =~ m/Perform progressive alignment/) {
      $position = $i;
      last;
    }
    if($out[$i] =~ /bpp\s+(\d+\.\d+)/) {
      $pairwiseBPP += $1;
    }
  }
  # now collecting progressive alignment bpps
  for(my $i = $position; $i < scalar(@out); $i++)
  {
    if($out[$i] =~ /bpp\s+(\d+\.\d+)/) {
      $progBPP += $1;
    }
  }
  
  $qm->{progBPP} = $progBPP;
  $qm->{pairBPP} = $pairwiseBPP;
  
  # parse the timing information
  my ($realTime, $sysTime, $userTime);
  for(my $i = 0; $i < scalar(@out); $i++)
  {
    if($out[$i] =~ m/^real (\d+\.\d+)/)
    {
      $realTime = $1;
      next;
    }
    if($out[$i] =~ m/^user (\d+\.\d+)/)
    {
      $userTime = $1;
      next;
    }
    if($out[$i] =~ m/^sys (\d+\.\d+)/)
    {
      $sysTime = $1;
      next;
    }
  }
  
  #print "user $userTime, sys $sysTime, real $realTime\n";
  
  $qm->{userTime} = $userTime;
  $qm->{sysTime} = $sysTime;
  $qm->{realTime} = $realTime;
  
  
  # extract apsi
  my $apsi;
  if ($rawFile =~ /apsi\-(\d+)/)
  {
    $apsi = $1;
  }
  # extract sci
  my $sci;
  if ($rawFile =~ /sci\-(\d+)/)
  {
    $sci = $1;
  }  
  $qm->{sci} = $sci;
  $qm->{apsi} = $apsi;
  
  # store input file
  $qm->{name} = $rawFile;

  # Evaluation
  
  # the path to the output file
  my $outputFile = $jobPrivateDir . "/results/result.aln";
  sanitizeOutput($outputFile);
  #~ system("sed --in-place 's/CLUSTAL W/CLUSTAL W(1.83) multiple sequence alignment/' $outputFile");
  
  
  $qm->{outputFile} = $outputFile;
  
  # call compalignp
  print "/home/meinzern/Hiwi/ParameterOptimizationProject/compalignp -t $outputFile -r $refFile\n";
  my $compalignOutput = `/home/meinzern/Hiwi/ParameterOptimizationProject/compalignp -t $outputFile -r $refFile`;
  chomp $compalignOutput;
  
  print "compalign score: $compalignOutput\n";
  
  $qm->{"SPS"} = $compalignOutput;
  
  return $result;
}

sub postprocessing
{
  
}
# objectiveFunction($results, $baseDir, $parameterSet, $logFileHandle, $failedDataArray[$auxFileHandle])
# auxfilehandle is only passed if --auxOutput was given to benchmarkPilot
sub objectiveFunction
{
  my $results = shift;
  my $baseDir = shift;
  my $params = shift;
  my $logFile = shift;
  my $failedData = shift;
  my $auxFile = shift;
  
  # run mcc calculating script for all results
  # first generate one string with all filenames
  my @keys = keys(%{$results});
  my $fileString = "";
  for(my $i = 0; $i < scalar(@keys); $i++) {
    $fileString .= $results->{$keys[$i]}->{outputFile} . " ";
  }
  print $logFile "/scratch/1/schmiedc/Niklas/mcc/aln_mcc -f=/scratch/1/schmiedc/Niklas/mcc/structure-annotation $fileString";
  my $mccOut = `/scratch/1/schmiedc/Niklas/mcc/aln_mcc -f=/scratch/1/schmiedc/Niklas/mcc/structure-annotation $fileString`;

  # parse the aln_mcc output
  my @out = split /\n/ , $mccOut;
  
  my %mccResults;
  for(my $i = 0; $i < scalar(@out); $i++) {
    if($out[$i] =~ /^(.+)\s+(.+)\s+(.+)\s+(.+)\s+(.+)\s+(.+)\s+(.+)\s+(.+)\s+(.+)/) {
      my $result = {"tp" => $2, "fp" => $3, "fn" => $4, "tn" => $5, "ppv" => $6, "sens" => $7, "mcc" => $8, "sqrt(sens*ppv)" => $9};
      $mccResults{$1} = $result;
    }
  }
  

  my $runs = scalar(keys(%{$results}));
  my $hits = 0;
  # Write logfile
  print $auxFile "Tool\t\t\tAPSI\tSPI\tSPS\tBPP(pair)\tBPP(prog)\ttp\tfp\tfn\ttn\t\tppv\tsens\tmcc\tsqrt(sens*ppv)\tusrTime\tSysTime\tRealTime\tname\n";
  while(my ($key,$value) = each(%{$results}))
  {
    $hits += $value->{"SPS"};
    
    # get mcc results
    my $mccResult = $mccResults{$value->{outputFile}};
    
    my $delimiter = "\t";
    
    $delimiter .= "\t" if (length($mccResult->{tn}) <= 7);
    
    print $logFile $value->{outputFile} . "\n";
    print $auxFile "MLocarna/locarnaN\t" . $value->{apsi} . "\t" . $value->{sci} . "\t" . $value->{SPS} . "\t" .  $value->{pairBPP} . "\t\t" . $value->{progBPP} . "\t\t" .
          $mccResult->{tp} . "\t" . $mccResult->{fp} . "\t" . $mccResult->{fn} . "\t" . $mccResult->{tn} . $delimiter . $mccResult->{ppv} . "\t" . $mccResult->{sens} . "\t" . $mccResult->{mcc} . "\t" . $mccResult->{"sqrt(sens*ppv)"} . "\t\t" .
          $value->{userTime} . "\t" . $value->{sysTime} . "\t" . $value->{realTime} . "\t\t" . $value->{name} . "\n";

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

sub sanitizeOutput 
{
  my $file = shift;
  
  open(my $handle, "<$file");
  
  my @lines = <$handle>;
  
  close($handle);
  
  #system("mv $file $file_original");
  
  # change header
  $lines[0] = "CLUSTAL W(1.83) multiple sequence alignment\n";
  
  # run over lines and replace non standard gap sympbols ~ and _
  for(my $i = 1; $i < scalar(@lines); $i++) {
    
    if($lines[$i] =~ m/^(.+)\s+(.+)/) {
        my $id = $1;
        my $sequence = $2;
        
        $sequence =~ s/[_~]/-/g;
        
        $lines[$i] = $id . "\t" . $sequence . "\n";
    }
  }
  
  # overwrite the file
  open($handle, ">$file");
    for(my $i = 0; $i < scalar(@lines); $i++) {
      print $handle $lines[$i];
  }


  
  close($handle);
}

1;
