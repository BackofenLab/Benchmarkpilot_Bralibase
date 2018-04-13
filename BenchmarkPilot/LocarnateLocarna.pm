#!/usr/bin/perl

package LocarnateLocarna;

sub preprocessing
{

}

# function that gets called by a single cluster job for each data point
sub run
{
  $| = 1;
  # data is the name of the reference alignment file
  my $data = shift;
  
  my $rawFile = $data->{path};
  
  # choose the raw file instead of the ref file
  my $refFile = $rawFile;
  $rawFile =~ s/\.ref\./\.raw\./;
  
  
  my $parameterSet = shift;
  
  my $qm = shift;
  
  my $dir = shift;
  
  # create a private subdir for this job under the dir for the whole run
  my $jobPrivateDir = $dir . "JobID_" . $data->{"benchmarkPilotID"};
  mkdir($jobPrivateDir);
  
  # parse the parameters
  my $gapcost = $parameterSet->{"gapcost"};
  
  # indel cost are actually negative
  my $i = $gapcost * -1;
  
  #my $locarnaCall = "/home/meinzern/tools/locarna-1.7.2.6/bin/mlocarna --tgtdir $jobPrivateDir $rawFile --indel-open=0 --LP --indel=$i -p=0.001";
  my $locarnaCall = "/home/meinzern/tools/locarna-1.7.2.6/bin/locarnate --no-seq --no-struc --indel-opening=0 --indel=$i --no-stacking  $rawFile";
  my $timingPrefix = "/usr/bin/time -p ";
  #~ my $locarnaCall = "/home/meinzern/tools/locarna-1.7.2.6/bin/locarna -w 10000 --indel $i -p0.001 --indel-opening=0 $inFile1 $inFile2";
  print $locarnaCall . "\n";
  # change into the job directory
  chdir($jobPrivateDir);
  print "calling";
  my $out = `$timingPrefix $locarnaCall`;
  print $out;
  print "returned";
  ## Parse the output
  my @out = split /\n/, $out;
  
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
  my $outputFile = $jobPrivateDir . "/results";
  # extract "alignmentID" which is used by locarnate as subdir
  my $alignmentID = $rawFile;
  $alignmentID = substr($alignmentID, rindex($alignmentID, "/"));
  $alignmentID =~ s/\.fa$//;
  $outputFile .= $alignmentID . "/mult/tcoffee.aln";

  print "output file: $outputFile\n";
  
  # call compalignp
  my $compalignOutput = `/home/meinzern/Hiwi/ParameterOptimizationProject/compalignp -t $outputFile -r $refFile`;
  chomp $compalignOutput;
  
  print "compalign score: $compalignOutput\n";
  
  $qm->{"SPS"} = $compalignOutput;
  
  return $result;
}

sub postprocessing
{
  
}
# objectiveFunction($results, $baseDir, $parameterSet, $logFileHandle, [$auxFileHandle])
# auxfilehandle is only passed if --auxOutput was given to benchmarkPilot
sub objectiveFunction
{
  my $results = shift;
  my $baseDir = shift;
  my $params = shift;
  my $logFile = shift;
  my $auxFile = shift;
  
  my $hits = 0;
  my $runs = scalar(keys(%{$results}));
  print $auxFile "Tool\t\t\tAPSI\tSPI\tSPS\tMCC\tBPP(pair)\tBPP(prog)\tusrTime\tSysTime\tRealTime\tname\n";
  while(my ($key,$value) = each(%{$results}))
  {
    $hits += $value->{"SPS"};
    print $auxFile "Locarnate/locarna\t" . $value->{apsi} . "\t" . $value->{sci} . "\t" . $value->{SPS} . "\t" . "XXX\t" . $value->{pairBPP} . "\t\t" . $value->{progBPP} . "\t\t" .
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


1;
