#!/usr/local/perl/bin/perl


use strict;
use warnings;
use Getopt::Long;
use Pod::Usage;
use Storable;
use Storable qw(fd_retrieve store_fd);
use Data::Dumper;
use IO::Socket;
use Sys::Hostname;
use File::Temp;
use Cwd;

use threads;
use threads::shared;

use feature "switch";

use parametersetGenerator;

use constant TEMPDATAFILE => "parameterOptimizer_serializedData";
use constant TEMPPARAMFILE => "parameterOptimizer_serializedParameters";

use constant RESULTFOLDER => "BenchmarkPilotResults";

# the path to the qsub binary: this is used to determine if qsub is present
use constant QSUBBIN => "/opt/sge-6.0/bin/lx24-amd64/qsub";

use constant PORT => 25041;
use constant VERSION => 0.1;

=head1 NAME

benchmarkPilot.pl 

=head1 SYNOPSIS

benchmarkPilot.pl -t <tool> -p <parameterSet> [-d <dataset> -f -c <chunksize> -l
    -b <basedir> --noPreprocessing --logfile <logfilepath>
    --auxOutput <auxOutputpath>]


    This is an automated benchmarking and parameter optimization tool especially
    designed for use with an SGE cluster.

AUTHOR: Niklas Meinzer <meinzern@informatik.uni-freiburg.de>

OPTIONS

		
        -d  <DATABASE:DataIdentifier>
            specifies the database of the test data and the database specific
            data identifier (e.g.: BRALIbase:k2/tRNA)
            The module DatabaseManagerDATABASE.pm must exist
            If this option is not given benchmark pilot will just run
            the tool once for each parameter set

        -t  the wrapper module for the benchmarked tool (if you have
            "Tool.pm" pass "Tool")
        
        -p  The file specifying the parameters and the ranges
        
        -f  force computation (history entries will be ignored)
        
        -c  Gives the chunk size, i.e. the number of data points each
            array job will compute (default is 1)
        
        -b  The directory under which all output will be generated
        
        --noPreprocessing skips preprocessing (e.g. if preprocessing output
            is already in place)

        --noPostprocessing skips postprocessing
        
        --logfile give logfile path (default is 
            <basedir>/BenchmarkPilotResults/<Date>.log
        
        --auxOutput filename of an additional output file only the modules
            objective function has access to
            
        --noPlot skips the plot creation at end of run
        
        --timeout maximum time in seconds single cluster jobs are allowed to take

        --keepTempDir the directory where all datapoints and parameter sets
                      are stored for the cluster jobs is by default deleted
                      at the end. If this option is given it will not be deleted
                      for debugging purposes

        --port  the port used for network communication (Default is 25041)
        	
        		
EXAMPLES
	


=cut

# push database manager dir to include path
BEGIN {
  push(@INC, "./DatabaseManagers");
  push(@INC, "./Tools");
}

$SIG{INT} = \&onInterrupt;

$| = 1; #autoflush on

my $parameterFile = undef;
our $baseDir = getcwd() . "/";
our $calledFromDir = `pwd`;
chomp $calledFromDir;
our $local = '';
my $tool = undef;
my $forceCalculation = '';
my $chunkSize = 1;
my $testData = "";
my $skipPreprocessing = '';
my $logFilePath = '';
my $auxOutput = undef;
my $skipPlotting = undef;
my $jobTimeout = undef;
my $keepTempDir = undef;
my $skipPostprocessing = undef;
our $usedPort = undef;
GetOptions ('c=i' => \$chunkSize,
            'p=s' => \$parameterFile,
            't=s' => \$tool,
            'l' => \$local,
            'd=s' => \$testData,
            'f' => \$forceCalculation,
            'b=s' => \$baseDir,
            'noPreprocessing' => \$skipPreprocessing,
            'noPostprocessing' => \$skipPostprocessing,
            'logfile' => \$logFilePath,
            'auxOutput=s' => \$auxOutput,
            'noPlot' => \$skipPlotting,
            'timeout=i' => \$jobTimeout,
            'keepTempDir' => \$keepTempDir,
            'port=i' => \$usedPort);

# Create the results dir, if it does not exist
our $resultDir = ($baseDir . RESULTFOLDER);
mkdir $resultDir if(! -d $resultDir);
mkdir $baseDir . "clusterOut" if(! -d $baseDir . "ClusterOut");
$resultDir .= "/";

# check if tool was given
if(!defined $tool)
{
  pod2usage("No tool given!\n");
}

# give warning
my $nodata = 0;
if($testData eq "")
{
  print "No test data was given; will run $tool once for each parameter set " .
         "with no data!\n";
  $nodata = 1;
  $testData = "no-Data";
}

# determine the port that is used
if (defined $usedPort ) {
  # check if port is in accessible range
  if ($usedPort < 1024) {
    pod2usage("Cant used port $usedPort! Must be higher than 1024!");
  }
} else {
  $usedPort = PORT;
}

# if local was not selected check if qsub is known to the system
# if not, this script is not run on the cluster headnode
# so it needs to exit with an error message
if (! $local) {
  if (!-e QSUBBIN) {
    pod2usage("Could not find qsub binary! If you want to use the cluster, this script must run on biui!\n" .
              "If you want to run on your local machine use the -l flag.\n" .
              "If you get this error message while on biui, the path of the qsub executable might have changed. In that case\n" .
              "please compare the value of the constant QSUBBIN with the return value of \"which qsub\" and correct the constant if neccesary.");
  }
}

# determine the database that is used
# it should be the first part of the $testData string until the ":"
my $DBmanager;
if (not $nodata) {
  my @testDataSplitted = split /:/, $testData;
  if (scalar(@testDataSplitted) != 2) {
    pod2usage("Invalid test data string!\n");
  }
  my $requestedDBManager = $testDataSplitted[0];
  $testData = $testDataSplitted[1];
  # try to import the DB Manager
  my $DBManagerModule = "DatabaseManager$requestedDBManager";
  eval "require DatabaseManager$requestedDBManager;";

  if($@) { pod2usage("Error while importing DBManger!\n
                       Make sure DatabaseManager$requestedDBManager.pm is in
                       ./DatabaseManagers\n");}

  # create a new instance
  eval "\$DBmanager = $DBManagerModule->new();";
}
my($se,$min,$hour,$mday,$mon,$year,$wday,$yday) = localtime;


my $sanitizedDataPath = $testData;
$sanitizedDataPath =~ s/\//-/g;
$sanitizedDataPath = "none" if ($nodata);

our $logPrefix = ($year+1900) ."-" . ($mon+1) . "-" . $mday . " " . $hour . ":". $min . ":" . $se ." Tool: $tool Dataset: $sanitizedDataPath";
if(!$logFilePath)
{
  $logFilePath = $resultDir . $logPrefix . ".log";
}

# Import Tool
eval "require $tool;";
if($@) { pod2usage("Error loading $tool.pm\n" .
                   "Make sure it is in one of the include directories\n") }

$chunkSize = 1 if(!defined $chunkSize);
if($chunkSize < 1)
{
  pod2usage("Invalid chunk size! Must be greater than 0 \n");
}

# open logfile
our $logFileHandle;
open $logFileHandle , ">$logFilePath";
printLogFileHeader($tool, $testData);

# open aux file
our $auxOutputFilehandle;
if(defined $auxOutput) {
  open $auxOutputFilehandle, ">$resultDir" . "$auxOutput";
}


# Create a temporary under the baseDir
my $tempDir = File::Temp->newdir( "temp_XXXXXXXXX" , DIR     => $baseDir,
                                  CLEANUP => 0,
                         );
                         
$tempDir .= "/";

# SGE Task ID
our $SGETaskID = undef;

print("parsing parameterfile...");
my $pG = parametersetGenerator->new($parameterFile);
print "done\n";

my $dataset = {"data" => []};
if (not $nodata) {
  print("Fetching dataset...");
  $dataset = $DBmanager->getElements($testData);
  print("done\n");
}
  my $history = getRunHistory($tool, $testData, $baseDir);
################################
# DEBUG ONLY
if(0)
{
  my $newData = [];
  #shift(@{$dataset->{"data"}});
  foreach my $i (0...20)
  {
    push(@{$newData}, shift(@{$dataset->{"data"}}));
  }
  $dataset->{"data"} = $newData;
}
###############################


my $activeParam = -1;
my $bestScore = -1;

my $hostname = hostname;
# Open Socket
our $sock = IO::Socket::INET->new(Listen => 500,
                              LocalAddr => $hostname,
                              LocalPort => $usedPort,
                              Proto => 'tcp');
                              
die("couldn't create socket\nProbably blocked from previous run. " .
    "Wait a couple of seconds and try again!\n") unless defined $sock;

  
# Write the temporary scripts to disk
my $scriptname = $tempDir . "ParameterOptimizer_tempScript.pl";
writePerlScript($tool, $scriptname, $hostname, $baseDir, $tempDir);
system("chmod +x $scriptname");
my $paramFile = $tempDir . TEMPPARAMFILE; 
my $cmd = "$scriptname -p $paramFile -d " . $tempDir . TEMPDATAFILE;
my $shellscriptname = $tempDir . "benchmarkPilot.sh";
writeShellScript($shellscriptname, $baseDir, $cmd);


# PREPROCESSING
# write both perl script and shellwrapper
print "Preprocessing...";
if(! $skipPreprocessing)
  {
  my $preprocessingShellscriptname = "benchmark_pilot_preprocessing.sh";
  my $preprocessingPerlscriptname = "benchmark_pilot_preprocessing.pl";
  my $preprocessingDataFile = $tempDir . "benchmark_pilot_preprocessing.data";
  store($dataset->{"data"}, $preprocessingDataFile);
  writePreprocessingScripts($preprocessingShellscriptname, $preprocessingPerlscriptname , $tool, $baseDir, $tempDir, $preprocessingDataFile);
  if($local)
  {
    system("perl ".$tempDir.$preprocessingPerlscriptname);
  }
  else
  {
    my $cmd = $tempDir . $preprocessingShellscriptname;
    $SGETaskID = `qsub $cmd`;
    my @temp = split /\s/, $SGETaskID;
    $SGETaskID = $temp[2];
    #print $SGETaskID;
  }
  # create a thread that waits for the result
  my $gotAnswer :shared = 0;
  my $preprocessingAcceptorThread = threads->create(sub { $sock->accept(); $gotAnswer = 1});
  # periodically check if cluster job still exists
  while(1) {
    sleep(5);
    my $jobgone = 0;
    my $temp = `qstat -l $SGETaskID`;
    $jobgone = 1 if (! $temp =~ m/^=/);
    last if ($gotAnswer);
    if ($jobgone) {
      $preprocessingAcceptorThread->detach();
      print "something went wrong!";
    }
  }
  $preprocessingAcceptorThread->join();
  print("done!\n");
  $SGETaskID = undef;
}
else
{
  print("skipped!\n");
}

# Write Datafiles

my $datacounter = scalar(@{$dataset->{"data"}});
# remember the data ids for error messages later
my @dataIDs;
my $chunkCounter = 0;
while(scalar(@{$dataset->{"data"}}) > 0)
{
  my $dataFile = $tempDir . TEMPDATAFILE . "_$chunkCounter";
  #~d $Jobs{$datacounter} =  $dataFile;
  
  # assemble data chunk
  my $dataChunk = [];
  for(my $j = 0; $j < $chunkSize; $j++)
  {
    my $newData = shift(@{$dataset->{"data"}});
    push(@dataIDs, $newData->{"id"});
    $newData->{"benchmarkPilotID"} = ($chunkCounter * $chunkSize) + $j;
    push(@{$dataChunk}, $newData);
    last if (scalar(@{$dataset->{"data"}}) <= 0);
  }
  $chunkCounter++;
  
  # Store data element in file
  store $dataChunk, $dataFile;
}
# if no data is given we still need chunkcounter to be 1 for anything to run
# also we need a fake datachunk
if($nodata) {
  $chunkCounter = 1;
  my $dataChunk = [{"benchmarkPilotID" => "dummy"}];
  my $dataFile = $tempDir . TEMPDATAFILE . "_0";

  store $dataChunk, $dataFile;
  print "storing $dataFile\n";
  $datacounter = 1;
}

# before entering main loop, summarize the run
print "\nStarting run over $datacounter datapoints (in $chunkCounter chunks)\n";
print $pG->numOfSets . " parameter sets will be tested.\n";
print (($pG->numOfSets * $chunkCounter) . " cluster jobs will be startet, issuing " . ($pG->numOfSets * $datacounter) . " single $tool calls\n");
print $logFileHandle "\nStarting run over $datacounter datapoints (in $chunkCounter chunks)\n";
print $logFileHandle $pG->numOfSets . " parameter sets will be tested.\n";
print $logFileHandle (($pG->numOfSets * $chunkCounter) . " cluster jobs will be startet, issuing " . ($pG->numOfSets * $datacounter) . " single $tool calls\n");
#my $dispose = <>;

print $logFileHandle "\nENTERING MAIN LOOP:\n";
print $logFileHandle "\n===================\n";
print "Entering main loop...\n";

my $plotRawData;

while(my $params = $pG->next())
{
  my $runcounter = 0;
  
  if($params->{"ACTIVE"} != $activeParam)
  {
    $pG->plotData($baseDir . "benchmarkPilotRawData_$activeParam", $resultDir . $logPrefix . " parameter: $activeParam ",  $activeParam, $testData, $tool) if ($activeParam != -1 and !defined $skipPlotting);
    $activeParam = $params->{"ACTIVE"};
    $bestScore = -1;
    print "Active parameter: $activeParam\n";
    if(defined $plotRawData)
    {
      close $plotRawData;
    }
    open $plotRawData, ">" . $baseDir . "benchmarkPilotRawData_$activeParam";

  }
  # Store parameter in file
  store $params, $paramFile;
  
  # write Parameters to Log
  print $logFileHandle "\n\nTesting the following parameters:\n";
  while( my ($key, $value) = each(%{$params}))
  {
    next if $key eq "ACTIVE";
    next if $key =~ m/^!/;
    print $logFileHandle $key . " ". $value  . ",";
  }
  print $logFileHandle "\n";
  # Serialize parameter set for history lookup
  my $serializedParameters = parametersetGenerator::parameterSetToString($params);
  
  # create Feedback hash
  my %Feedback;
  # failed data
  my @failedData;
  
  # check if data for this parameterset already exists
  if(!$forceCalculation && defined $history->{$serializedParameters})
  {
    %Feedback = %{$history->{$serializedParameters}};
    print "Found matching history entry for the following parameter set - no calculations are needed";
  }else
  {
    # Actually calculate results if they are not in the history
    if($local)
    {
      foreach my $i (0 ... $chunkCounter-1)
      {
        system($scriptname." -p ".$tempDir . "parameterOptimizer_serializedParameters -d " . $tempDir . "parameterOptimizer_serializedData_$i -i $i &");
      }
    }else
    {
      my $cmd = "qsub -t 1-". ($chunkCounter) ." $shellscriptname";
      $SGETaskID = `$cmd`;
      my @temp = split /\s/, $SGETaskID;
      $SGETaskID = $temp[2];
    }
    
    my $abort = undef;
    while(scalar(keys(%Feedback)) < $datacounter)
    {
      my $incomingData;
      # wait for result (abort after timeout if it is set)
      eval {
        local $SIG{ALRM} = sub {die ""};
        alarm($jobTimeout) if defined ($jobTimeout);
        $incomingData = $sock->accept();
        alarm(0)
      };
      if ($@) {
        print $logFileHandle "Aborting run after not getting any results for $jobTimeout seconds!\n";
        $abort = 1;
        system("qdel $SGETaskID");
        last;
      }
      my $returnHash = fd_retrieve($incomingData);
      
      
      $Feedback{$returnHash->{"id"}} = $returnHash;
      
      #process quality measures
      #processQualityMeasures(\%acc, $returnHash, $qmSettings);

      # print visual feedback
      my $numResultsDone = scalar(keys(%Feedback));
      my $percentageResultsDone = $numResultsDone/$datacounter * 50;
      print "\r|";
      for (my $i = 0; $i < $percentageResultsDone; $i++) {
        print "=";
      }
      for (my $i = 0; $i < (50 - $percentageResultsDone); $i++) {
        print " ";
      }
      print "|  ($numResultsDone/$datacounter)";
      $runcounter++;
    }
    
    # handle abort 
    if(defined $abort) {
      print $logFileHandle "The jobs working on the following data failed to report:\n";
      for(my $i = 0; $i < $datacounter; $i++)
      {
        print $logFileHandle $dataIDs[$i] . "\n"  if(!defined $Feedback{$i});
        push(@failedData, $dataIDs[$i]);
      }
    }
    $SGETaskID = undef;
    # store results in History
    
    $history->{$serializedParameters} = \%Feedback;
  }
  

  
  print "\n";
  print $logFileHandle "### Begin Objective Function ###\n";
  my $finalValue = processQualityMeasures(\%Feedback, $tool, $params, \@failedData);
  # check if the result is defined
  if (!defined $finalValue) {
    print "Warning: Undefined Value recieved form objectiveFunction!\n";
  }
  print $logFileHandle "### End Objective Function ###\n";
  
    # print plot raw data
  my $plotValue = (defined $finalValue)?$finalValue:-1;
  print $plotRawData ($params->{"!ACTIVE-VALUE"}  . "\t$plotValue\n");
  if(defined $finalValue && $finalValue > $bestScore)
  {
    $bestScore = $finalValue;
    $pG->reportBest($bestScore);
    print "bestFound!\n";
    print $logFileHandle "Current Best\n";
  }
  print "evaluated parameter set: ";
  while(my ($key, $value) = each(%{$params}))
  {
    next if $key eq "ACTIVE";
    next if $key =~ m/^!/;
    print "$key = $value\t";
  }
  print "\naverage value: " . $plotValue. "\n";

print "\n";
}

# plot last parameter
$pG->plotData($baseDir . "benchmarkPilotRawData_$activeParam", $resultDir . $logPrefix . " parameter: $activeParam ",  
              $activeParam, $testData, $tool) if ($activeParam != -1 and !defined $skipPlotting);

# delete datafiles and parameterfiles
foreach my $i (0 ... $datacounter)
{
  unlink($baseDir . "parameterOptimizer_serializedData_$i");
  unlink($baseDir . "parameterOptimizer_serializedParameters");
}
($se,$min,$hour,$mday,$mon,$year,$wday,$yday) = localtime(time);
$year += 1900;
$se = "0" . $se if ($se < 10);
print $logFileHandle "\n\n====================================\n====================================\n";
print $logFileHandle "Run finished!\n";
print $logFileHandle "Time: $mday.$mon.$year $hour:$min:$se \n";
print $logFileHandle "\n\nResults:\n";

print "=======================================\n";
print "best parameter set: \n";
print "=======================================\n";
my $bestSet = $pG->getBestSet();
while(my ($key, $value) = each(%{$bestSet}))
{
  next if $key eq "VALUE";
  print "$key = $value\t";
  print $logFileHandle "$key = $value\t"
}
print "\nValue: " . $bestSet->{"VALUE"} . "\n";
print $logFileHandle "\nValue: " . $bestSet->{"VALUE"} . "\n";
print "ALL TEST DONE!\n";
$sock->close();


# postprocessing
if (! defined $skipPostprocessing) {
  eval "$tool"."::postprocessing();";
}
# Write history to file

storeHistory($tool, $testData, $baseDir, $history);

close $logFileHandle;
close $auxOutputFilehandle if (defined $auxOutputFilehandle);

# delete temp dir (if --keepTempDir option was not given)

if (! defined $keepTempDir) {
  system("rm -rf $tempDir");
}


sub processQualityMeasures
{
  my $Feedback = shift;
  my $toolname = shift;
  my $parameterSet = shift;
  my $failedData = shift;
  
  my $value;
  eval "\$value = $toolname"."::objectiveFunction(\$Feedback, \$baseDir,\$parameterSet, \$logFileHandle, \$failedData, \$auxOutputFilehandle);";
  if($@) { print "Fehler: $@" }
  
  return $value;
}

sub writePerlScript
{
  my $toolname = shift;
  my $scriptname = shift;
  my $hostname = shift;
  my $baseDir = shift;
  my $tempDir = shift;
  
  open(SCRIPT, ">$scriptname");
  
  print SCRIPT "#!/usr/bin/perl\n";
  
  print SCRIPT "#THIS SCRIPT HAS BEEN AUTO-GENERATED BY BENCHMARKPILOT )\n\n";
  
  print SCRIPT "BEGIN{  push \@INC,\"$calledFromDir\";}";
  
  print SCRIPT "\nuse strict;\nuse warnings;\nuse Storable;\nuse IO::Socket;\nuse Getopt::Std;\n\n";
  
  print SCRIPT "use $toolname;\n\n\n";
  
  print SCRIPT "my %options=();\ngetopts(\"p:d:i:\", \\%options);\n";
  
  print SCRIPT "my \$data = retrieve(\$options{\"d\"});\n";
  print SCRIPT "my \$params = retrieve(\$options{'p'});\n";
  #print SCRIPT "my \$id = \$options{'i'};\n";
  
  print SCRIPT 'foreach my $dataElement (@{$data})' . "\n{\n";
  print SCRIPT "\n\tmy \%qm = ();\n";
  
  print SCRIPT "\n\tmy \$return = ".$toolname."::run(\$dataElement, \$params, \\\%qm, \"$tempDir\");\n";  
  
  print SCRIPT "\t" . '$qm{"id"} = $dataElement->{"benchmarkPilotID"};' . "\n\t";
  
  print SCRIPT "\tmy \$sock = IO::Socket::INET->new( PeerAddr => '$hostname', PeerPort => '".$usedPort."', Proto => 'tcp');\n";
  print SCRIPT "\tdie(\"Can't create Socket!\\n\") unless defined \$sock;\n\n";  
  
  print SCRIPT 'Storable::nstore_fd(\%qm, $sock);' . "\n";

  print SCRIPT '$sock->close();' ."\n";
  
  print SCRIPT "}";
  
  close(SCRIPT);
}

sub writeShellScript
{
  my $filename = shift;
  my $baseDir = shift;
  my $cmd = shift;
  
  open(SCRIPT, ">$filename");
  
  print SCRIPT "#!/bin/sh\n#\$ -l h_vmem=2G\n";
  print SCRIPT "#\$ -hard -l c_op2356=1\n";
  #~ print SCRIPT "#\$ -o $baseDir"."clusterOut/\$JOB_NAME.\$JOB_ID.\\\$SGE_TASK_ID.out\n";
  print SCRIPT "#\$ -o $baseDir/"."clusterOut/\n";
  #~ print SCRIPT "#\$ -e $baseDir" . "clusterOut/\$JOB_NAME.\$JOB_ID.\\\$SGE_TASK_ID.err\n";
  print SCRIPT "#\$ -e $baseDir/" . "clusterOut/\n";
  print SCRIPT "ID=\$((SGE_TASK_ID -1))\n";
  print SCRIPT $cmd . "_\$ID -i \$ID\n";
  close(SCRIPT);
}

sub writePreprocessingScripts
{
  my $scriptname = shift;
  my $perlScriptName = shift;
  my $toolname = shift;
  my $baseDir = shift;
  my $dir = shift;
  my $datafile = shift;
  
  my $SCRIPT; 
  
  # 1. Write perl script
  open($SCRIPT, ">$dir" . $perlScriptName);
  print $SCRIPT "#!/usr/bin/perl\n";
  
  print $SCRIPT "#THIS SCRIPT HAS BEEN AUTO-GENERATED BY BENCHMARK PILOT\n\n";
  print $SCRIPT "BEGIN{  push \@INC,\"$baseDir\";}";
  print $SCRIPT "\nuse strict;\nuse warnings;\nuse Storable;\nuse IO::Socket;\n\n";

  print $SCRIPT "use $toolname;\n\n\n";
  
  print $SCRIPT "my \$data = retrieve(\"$datafile\");\n";
  
  print $SCRIPT "$tool"."::preprocessing(\"$dir\", \$data);\n";
  
  print $SCRIPT "my \$sock = IO::Socket::INET->new( PeerAddr => '$hostname', PeerPort => '".$usedPort."', Proto => 'tcp');\n";
  
  print $SCRIPT 'print $sock "done";' . "\n";

  print $SCRIPT '$sock->close();' ."\n";
  
  close($SCRIPT);
  
  # 2. Write shell script
  open($SCRIPT, ">$dir". $scriptname);
  print $SCRIPT "#!\/bin\/sh\n#\$ -l h_vmem=2G\n";
  print $SCRIPT "#\$ -o $baseDir/"."clusterOut/\n";
  print $SCRIPT "#\$ -e $baseDir/" . "clusterOut/\n";
  print $SCRIPT "setup vrna185\n";
  print $SCRIPT "perl $dir"."$perlScriptName\n";
  
  close($SCRIPT);
}

sub getRunHistory
{
  my $tool = shift;
  my $name = shift;
  my $baseDir = shift;
  
  $name =~ s/\//-/g;
  
  if(! -e ($baseDir . "benchmarkPilot_history"))
  {
    mkdir($baseDir . "benchmarkPilot_history");
  }

  if(!-e ($baseDir . "benchmarkPilot_history/" . $tool))
  {
    mkdir($baseDir . "benchmarkPilot_history/" . $tool);
  }
    
  if(!-e ($baseDir . "benchmarkPilot_history/$tool/" . $name))
  {
    return {};
  }else
  {
    return retrieve($baseDir . "benchmarkPilot_history/$tool/" . $name);
  }
  
}

sub storeHistory
{
  my $tool = shift;
  my $name = shift;
  my $baseDir = shift;
  my $history = shift;
  
  $name =~ s/\//-/g;
  
  store $history, ($baseDir . "benchmarkPilot_history/$tool/" . $name);
}

sub onInterrupt {
    $SIG{INT} = \&onInterrupt;
    if(!$local)
    {
      if(defined $SGETaskID)
      {
        system("qdel $SGETaskID");
      }
    }
    if(defined $sock)
    {
      $sock->close();
    }
    print "Benchmark pilot has been interrupted manually!\n";
    exit;
}

sub printLogFileHeader
{
  my $tool = shift;
  my $data = shift;
  my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
  print $logFileHandle "Benchmark Pilot (Version ".VERSION.") logfile\n";
  print $logFileHandle "=============================================\n\n";
  print $logFileHandle "Run Info:\n";
  print $logFileHandle "=========\n";
  print $logFileHandle "Time:\t$mday.".($mon+1).".".($year+1900)." $hour:$min\n";
  print $logFileHandle "Tool:\t$tool\n";
  print $logFileHandle "Dataset:\t$data\n";
}
