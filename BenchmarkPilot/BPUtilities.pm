package BPUtilities;
use strict;
use warnings;
use Term::ANSIColor;

# colors a string red
sub redString {
  return (color("red") . shift . color("reset"));
}


1;
