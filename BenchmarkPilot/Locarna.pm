#!/usr/bin/perl

package Locarna;

sub preprocessing
{
  #~ my $dir = shift; # the path of the temporary directory
  #~ my $data = shift;
  #~ 
  #~ chdir($dir);
  #~ mkdir("inputFasta");
  #~ chdir("inputFasta");
  #~ foreach my $dataElement (@{$data})
  #~ {
    #~ my $filename = $dataElement->{"name"};
    #~ $filename =~ s/\//-/g;
#~ 
    #~ # Write each sequence in a separate fasta file
    #~ foreach my $sequence (@{$dataElement->{"elements"}})
    #~ {
      #~ my $id = $sequence->{"id"};
      #~ 
      #~ my $completeFilename = $filename . $id . ".fasta";
		#~ 
      #~ open(my $fastaFile, ">", $completeFilename) or die("$! : $completeFilename \n");
      #~ 
      #~ print $fastaFile ">$id\n";
      #~ print $fastaFile uc($sequence->{sequence}) . "\n";
      #~ 
      #~ close($fastaFile);
    #~ }
    #~ 
  #~ }
}

# ($dataElement, $params, \%qm, "/scratch/1/muellert/TeamProjekt/Output/temp_JhRyijRbA/")

# function that gets called by a single cluster job for each data point
sub run
{
  my $data = shift;
  
  my $parameterSet = shift;
  
  my $qm = shift;
  
  my $dir = shift;
  
  my $start = time;
  
  # my $bralibase_path = "/scratch/1/muellert/TeamProjekt/Output/Test_BraliBase_Results/"; 
  # my $bralibase_path = "/scratch/1/muellert/TeamProjekt/Output/BraliBaseOutput_70_NegativTestSet/"; 
  # my $bralibase_path = "/scratch/1/muellert/TeamProjekt/Output/Updated_BralibaseOutput_20/"; 
  # my $bralibase_path = "/scratch/1/muellert/TeamProjekt/Output/Updated_BralibaseOutput_70/"; 
  # my $bralibase_path = "/scratch/1/muellert/TeamProjekt/Output/Updated_BralibaseOutput_NegativeTestSet_20/"; 
 
  my $bralibase_path = "/scratch/1/muellert/TeamProjekt/Output/TestPositionCon20/";
  # my $bralibase_path = "/scratch/1/muellert/TeamProjekt/Output/ModifiedBralibase-Context20/"; 
 
  
  my $file = "results/result.aln";
  
  my $scoreFile = "results/result_prog.aln";
 
  
  my $rawFile = $bralibase_path . $data->{"name"} . ".raw.fa";
  my $refFile = $bralibase_path . $data->{"name"} . ".ref.fa";
  # my $inFile = $bralibase_path . $data->{"name"} ;
    
  #print "filename: " . $refFile. "\n";
  
  
  
  #my $file = $bralibase_path . $data;
  
  # parse the parameters
  #my $gapcost = $parameterSet->{"gapcost"};
  
  # indel cost are actually negative
  my $i = $gapcost * -1;
  
  my $a = $data->{"elements"}->[0]->{"sequence"};
  my $b = $data->{"elements"}->[1]->{"sequence"};
  
  
  my $dataID = $data->{"name"};
  $dataID =~ s/\//-/g;
 
  
  
  
  
  # create a private subdir for this job under the dir for the whole run
	my $jobPrivateDir = $dir . "_" . $data->{"benchmarkPilotID"};
	mkdir($jobPrivateDir);

	# change to private directory -> file constraints is written there
	chdir $jobPrivateDir or die "Couldn't change directory to $jobPrivateDir: $!";
  
  
 
  
  #~ my $locarnaCall = "/home/meinzern/tools/locarna-1.7.2.6/bin/locarna_n -w 10000 --indel $i -p0.001 --prob_unpaired_in_loop_threshold=0.00001 --prob_basepair_in_loop_threshold=0.00001 $inFile1 $inFile2";
  my $locarnaCall = "/usr/local/user/locarna/1.7.16/bin/mlocarna -v --tgtdir $jobPrivateDir --pw-aligner-options \"--sequ-local on\" --local-progressive $rawFile";
  # print $locarnaCall . "\n";
  
  my $out = `$locarnaCall 2>&1`;

  ## Parse the locarna output
  my @out = split /\n/, $out;
  
  my ($predictonHash_ref, $referenceHash_ref) = getLocarnaFeaturs($out, $rawFile, $refFile);
  
  my $locarnaScore = "not there";
  
  # find the first line that starts with "Score"
  # this is the start of the regular output, there are possible warnings before that
  my $offset = 0;
  for(my $i = 0; $i < scalar(@out); $i++){
	 last if ($out[$i] =~ /^Score/);
	 $offset++;
  }  
 
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
    

  # $qm->{"hitRate"} = $actually/$total;


  # $qm->{"time"} =  $totalTime - $bppTime;
  $qm->{"score"} =  $locarnaScore;
  $qm->{"name"} = $locarnaCall;
  $qm->{"file"} = $rawFile;
  # $qm->{"sps"} =  $out2;

  
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
    # print "Key: " . $key . "\n";
    # print "Value: " .  $value->{"SPS_Score"} . "\n";
    $hits += $value->{"hitRate"};
    # print $logFile $value->{"hitRate"} . " " . $hits . "\n";
    print $logFile $value->{"file"} . "\t" . $value->{"score"} . "\n";
  }
  my $average = ($runs==0)?0:$hits/$runs;
  print $logFile "avg SPS: " . $average . "\n";
  return $average;
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
  #~ print @seq;
  #~ print "\n";
  #~ print $alignment->{"sequenceWithGaps"} . "\n";
  
  return \@seq;
}


sub sanitizeOutput
{
     my $file = shift;
     
     # print "Changing Clustal W format \n";

     open(file1,"<$file") || die "Cannot open $file \n";

     my @input = <file1>;
     my @output;

     # change header
     $input[0] = "CLUSTAL W(1.83) multiple sequence alignment\n";

     #delete constraints
     foreach my $line(@input){
	 # if($line !~ /^#/){ print $line . "\n"; };
     if($line !~ /^#/){ push @output,$line; };
     }

     open(OUT,">$file");
     foreach my $line(@output){print OUT $line;};
     close(OUT);
}


#########################Teresa's part################
sub getLocarnaFeaturs{
	my $out = $_[0];
	my $rawFile = $_[1];
	my $refFile = $_[2];

	#use as sequence index in one file
	my @alpabet = ("A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M", "N", "O");
	
	my $predictonHash_ref = getLocarnaScoreAndPositions($out);
	
	foreach my $key (sort keys %$predictonHash_ref){
		# print "$key\n";
		
		print "$key: $$predictonHash_ref{$key} \n";
		}
	
	my $referenceHash_ref = getRefPositions($rawFile, $refFile, \@alpabet);
	
	return $predictonHash_ref, $referenceHash_ref

}
	

sub getRefPositions{
	my $rawFile = $_[0];
	my $refFile = $_[1];
	my $alpabet_ref = $_[2];
	
	my %referenceHash;
	my @rawIdArray;
	my @refIdArray;
	
	my $idRaw;
	my $idRef;
	
	my @localStart;
	my @localEnd;
	
	my $localStart;
	my $localEnd;
	
	my $localStartName;
	my $localEndName;
	
	my $id_Identifier = ">";

	
	# get the Id's of of the raw and ref fa files and save ID's into arrays
	open(GetIDPositionsRaw, "<$rawFile") or die "cannot open < $rawFile: $!";
	
	foreach my $line (<GetIDPositionsRaw>)  {
		chomp($line); 
		# just need the ID's
		if ($line =~ m/$id_Identifier/) {
			#print "ID: $line \n";
			push(@rawIdArray, $line);		
			}
		}
	close(GetIDPositionsRaw);
	

	open(GetIDPositionsRef, "<$refFile") or die "cannot open < $refFile: $!";
	
	foreach my $line (<GetIDPositionsRef>)  {
		chomp($line); 
		# just need the ID's
		if ($line =~ m/$id_Identifier/) {
			#print "ID: $line \n";
			push(@refIdArray, $line);		
			}
		}
	close(GetIDPositionsRef);
	
	# find positions
	
	my $arraylenthraw = scalar @rawIdArray;
	my $arraylenthref = scalar @refIdArray;
	
	if($arraylenthraw != $arraylenthref){
		# if this error occurs the program shuold stop!
		print "Error: the raw and ref file contains different amount of id's";
		}
	
	for (my $i = 0; $i<= $arraylenthraw - 1; $i++){
		#print "$i\n";
		$idRaw = $rawIdArray[$i];
		$idRef = $refIdArray[$i];
		
		#print "RefID: $idRef\n";
		#print "RawID: $idRaw\n";
		
		$idRaw =~ />(.+?)\.(\d+?)_(\d+?)-(\d+)/;
					
		my $accesion_raw = $1;
		my $version_raw = $2;
		my $startpos_raw = $3;
		my $endpos_raw = $4;
		
		$idRef =~ />(.+?)\.(\d+?)_(\d+?)-(\d+)/;
					
		my $accesion_ref = $1;
		my $version_ref = $2;
		my $startpos_ref = $3;
		my $endpos_ref = $4;
		
		# forward strand
		if ($startpos_raw <= $endpos_raw && $startpos_ref <= $endpos_ref){
			
			# print "Endpos: $endpos_ref - $startpos_raw\n";
			
			my $start = $startpos_ref - $startpos_raw;
			my $end = $endpos_ref - $startpos_raw;
			
			# print "Start: $start End: $end\n";
			
			push(@localStart, $start);
			push(@localEnd, $end);
			}
		# revers strand
		elsif($startpos_raw >= $endpos_raw && $startpos_ref >= $endpos_ref)	{
			
			my $start = $endpos_ref - $endpos_raw;
			my $end = $startpos_ref - $endpos_raw;
		
			push(@localStart, $start);
			push(@localEnd, $end)
			}	
		else{
			print "Error: One strand seem to be forward the other reverse \n";
			}
		}
	
	
	
	my $arraylenth = scalar @localEnd ;
	
	for (my $i = 0; $i<= $arraylenthraw - 1; $i++){
		
		$localStart = $localStart[$i];
		$localEnd = $localEnd[$i];
		
		# print "Startpos: $localStart Endpos: $localEnd\n";
		
		my $indexLetter = shift(@$alpabet_ref);
		
		# print "Index: $indexLetter \n";
	
		$localStartName = "localStart" . $indexLetter;
		$localEndName = "localEnd" . $indexLetter;
		
		$referenceHash{ $localStartName } = $localStart; 
		$referenceHash{ $localEndName } = $localEnd; 
		}
	
	return \%referenceHash
	
	}	



# sub .....
sub getLocarnaScoreAndPositions{
	
	my $out = $_[0];   
	my $rawFile = $_[1];
	
	my %predictonHash;
	
	my $localStartA;
	my $localStartB;
	my $localEndA;
	my $localEndB;
	
	# print "\n OUTPUT: \n$out\n\n";
	
	my $score;
 
    if ($out =~ /HIT\s(.+?)\s(.+?)\s(.+?)\s(.+?)\s(.+?)\s/) {
	  $score = $1;
	  $localStartA = $2;
	  $localStartB = $3;
	  $localEndA = $4;
	  $localEndB = $5;
	  
		} 
    else {
	  $score = 0;
		}
      
    $predictonHash{ "localStartA" } = $localStartA; 
    $predictonHash{ "localStartB" } = $localStartB; 
    $predictonHash{ "localEndA" } = $localEndA; 
    $predictonHash{ "localEndB" } = $localEndB; 
    $predictonHash{ "score" } = $score; 
    
	# print "Score: $score\n";
	# print "SA: $localStartA SB: $localStartB EA: $localEndA EB: $localEndB\n";
	
	return  \%predictonHash;
	
	}



1;
