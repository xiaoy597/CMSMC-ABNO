#!/usr/bin/perl
use strict;
use warnings FATAL => 'all';

open FH, "c:/users/xiaoy/test.sql" or die "Can not open file.";
my $file_content = "";

while(<FH>){
    $file_content = $file_content . $_
}

my %PARAM = ();

$PARAM{"HOSTNM"} = "10.97.10.200";
$PARAM{"USERNM"} = "xiaoy";
$PARAM{"PASSWD"} = "CMSS2017";

my $HOSTNM = "10.97.10.200";
my $USERNM = "xiaoy";
my $PASSWD = "CMSS2017";

#my $z = eval($y);

my $result = eval("return \"" . $file_content . "\"");

print $result;

