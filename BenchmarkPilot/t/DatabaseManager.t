#!/usr/bin/perl -w

use strict;
use DatabaseManager;
use DatabaseManagerBRALIbase;

use Test::More qw(no_plan);

BEGIN
{
  print "\nTESTING DatabaseManager\n";
  print "=======================\n";
	use_ok("DatabaseManager");
}

my $DBManager = DatabaseManager->new();

is($DBManager->{"superProperty"}, 1);
ok(!defined $DBManager->{"property"});

#~ dies_ok{$DBManager->getElement()};


# Testing DatabaseManagerBRALIbase

my $Brali = DatabaseManagerBRALIbase->new();

is($Brali->{"superProperty"}, 1);
ok(defined $Brali->{"property"});


my $dataset = $Brali->getElements("k2/THI");

is(scalar(@{$dataset->{"data"}}), 321, "dataset size");
is(scalar(@{$dataset->{"data"}->[0]->{"elements"}}), 2, "dataset element size");

my $data = $Brali->parseBraliBaseFile("/scratch/db/BRALIBASE/k2/THI/THI.apsi-38.sci-68.no-1.ref.fa");

is(scalar(@{$data->{"elements"}}), 2, "parsed data size");
is($data->{"elements"}->[0]->{"id"}, "AJ414158.1_174343-174468", "parsed data id");
is($data->{"elements"}->[0]->{"sequence"}, "aggcucuugucggagugccuagcaccugcuuuuuuaggaaagcaaacgcaggcugagaccguuaauucgggauccgcggaaccugaucggguuaauacccgcgaagggaacaagaguaauuuaucg", "parsed data sequence");
is($data->{"elements"}->[0]->{"sequenceWithGaps"}, "aggcucuugucggagugccuagcaccugcuuuuuuaggaaagcaaacgcaggcugagaccguua-----------------------------------------------------auucgggauccgcggaaccuga-ucggguuaauacccgcgaagggaacaagaguaauuuaucg", "parsed data sequence with gaps");

$Brali = DatabaseManagerBRALIbase->new("./t/TestData/testBRALIBASE");
$dataset = $Brali->getElements("k2");
is(scalar(@{$dataset->{"data"}}), 4, "dataset size");

$Brali = DatabaseManagerBRALIbase->new();

$dataset = $Brali->getElements("k2");
