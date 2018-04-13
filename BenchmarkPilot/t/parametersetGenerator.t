#!/usr/bin/perl -w

use strict;

use Test::More qw(no_plan);
#~ use Test::Exception;
use parametersetGenerator;



my $parameterSet = parametersetGenerator::newIntervalParameter("t [6,10] 7");

is($parameterSet->{"low"}, 6, "low limit");
is($parameterSet->{"high"}, 10, "high limit");
is($parameterSet->{"name"}, "t", "name");
is($parameterSet->{"current"}, 7, "current");
is($parameterSet->{"best"}, 7, "best");

$parameterSet = parametersetGenerator::newIntervalParameter("j [3,100]");

is($parameterSet->{"low"}, 3, "low limit");
is($parameterSet->{"high"}, 100, "high limit");
is($parameterSet->{"name"}, "j", "name");
is($parameterSet->{"current"}, 3, "current");
is($parameterSet->{"best"}, 3, "best");
is($parameterSet->{"type"}, "interval", "type");

#~ dies_ok{$parameterSet = parametersetGenerator::newIntervalParameter("j [3,100] 1")};
#~ dies_ok{$parameterSet = parametersetGenerator::newIntervalParameter("j [3,100] 101")};


$parameterSet = parametersetGenerator::newBoolParameter("t");

is($parameterSet->{"name"}, "t", "name");
is($parameterSet->{"current"}, 0, "current");
is($parameterSet->{"best"}, 0, "best");
is($parameterSet->{"type"}, "bool", "type");


my $pG = parametersetGenerator->new("./t/TestData/parameters2");

is($pG->numOfSets(), 14, "testing numOfSets");
my $param = $pG->next();
is($param->{"t"}, 0, "first next call");
is($param->{"m"}, 0, "first next call");
is($param->{"i"}, 1, "first next call");
is($param->{"ACTIVE"}, 0, "active");
$param = $pG->next();
is($param->{"t"}, 1, "second next call");
is($param->{"m"}, 0, "second next call");
is($param->{"i"}, 1, "second next call");
is($param->{"ACTIVE"}, 0, "active");
$pG->reportBest(1);
$param = $pG->next();
is($param->{"t"}, 1, "third next call");
is($param->{"m"}, 0, "third next call");
is($param->{"i"}, 1, "third next call");
is($param->{"ACTIVE"}, 1, "active");
$param = $pG->next();
is($param->{"t"}, 1, "fourth next call");
is($param->{"m"}, 1, "fourth next call");
is($param->{"i"}, 1, "fourth next call");
is($param->{"ACTIVE"}, 1, "active");

$pG = parametersetGenerator->new("./t/TestData/parameters");

is($pG->numOfSets(), 15, "testing numOfSets");
is(scalar(@{$pG->{"parameters"}}), 3, "number of found parameters");
is($pG->{"parameters"}->[0]->{"name"}, "d", "found parameters name");
is($pG->{"parameters"}->[1]->{"name"}, "m", "found parameters name");
is($pG->{"parameters"}->[2]->{"name"}, "i", "found parameters name");
is($pG->{"parameters"}->[1]->{"stepsize"}, 2, "stepsize");
is($pG->{"parameters"}->[1]->{"high"}, 5, "high");
$param = $pG->next();
is($param->{"d"}, 0, "first next call");
is($param->{"m"}, 0, "first next call");
is($param->{"i"}, 1, "first next call");

is(parametersetGenerator::parameterSetToString($param), "d-0_i-1_m-0_");

$param = $pG->next();
is($param->{"d"}, 1, "second next call");
is($param->{"m"}, 0, "second next call");
is($param->{"i"}, 1, "second next call");

$pG = parametersetGenerator->new("./t/TestData/parameters3");
$param = $pG->next();
is($param->{"q"}, 0, "first next call");
$param = $pG->next();
is($param->{"q"}, 10, "second next call");
$param = $pG->next();
is($param->{"q"}, 20, "third next call");
$pG->reportBest(19);
$param = $pG->next();
is($param->{"q"}, 20, "fourth next call");
is($param->{"m"}, 0, "fourth next call");

is($pG->{"parameters"}->[0]->{"prettyName"}, "q", "prettyName");
is($pG->{"parameters"}->[1]->{"prettyName"}, "multiplier", "prettyName");

# Test parameters with decimal points

$pG = parametersetGenerator->new("./t/TestData/parameters4");
is($pG->{"parameters"}->[0]->{"low"}, 0.2, "decimal low");
is($pG->{"parameters"}->[0]->{"high"}, 6.4, "decimal high");
$param = $pG->next();
is($param->{"q"}, 0.2, "first next call");
$param = $pG->next();
is($param->{"q"}, 0.6, "first next call");


# test multiplying

$pG = parametersetGenerator->new("./t/TestData/parameters5");
$param = $pG->next();
is($param->{"q"}, 2, "first next call");
$param = $pG->next();
is($param->{"q"}, 4, "second next call");
$param = $pG->next();
is($param->{"q"}, 8, "third next call");
