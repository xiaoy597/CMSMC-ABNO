#!/usr/bin/perl
use strict;
use warnings FATAL => 'all';

my @a = ();

our $v1 = "abcd";

sub func1 {
    print $v1 . "\n";
}

print $#a . "\n";

func1;
