#!/usr/bin/perl -w

use strict;
use DataElement;

use Test::More qw(no_plan);
use Test::Exception;

BEGIN
{
  print "\nTESTING DataElement\n";
  print "=======================\n";
	use_ok("DataElement");
}
