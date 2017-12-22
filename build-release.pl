#!/usr/bin/perl
use strict;
use warnings FATAL => 'all';
use File::Copy;
use File::Copy::Recursive qw(dircopy);
use Time::localtime;
use File::Path;
use Archive::Zip  qw( :ERROR_CODES :CONSTANTS );

my $tc = localtime(time());
my $time = sprintf("%4d%02d%02d", $tc->year + 1900, $tc->mon + 1, $tc->mday);

rmtree('target') if (-e 'target');

my $release_dir = "target/release-$time";

mkpath($release_dir);

dircopy('sql-template', "$release_dir/sql-template");

copy('abno_incm.pl', "$release_dir/abno_incm.pl");
copy('abno_ddl.sql', "$release_dir/abno_ddl.sql");
copy('INSTALL.txt', "$release_dir/INSTALL.txt");

open(my $script_fh, "$release_dir/abno_incm.pl") or die "Can not open abno_incm.pl for processing.";

open(my $script_out_fh, "> $release_dir/abno_incm.pl.new") or die "Can not open abno_incm.pl.new for processing.";

while (<$script_fh>) {
    my $line = $_;
    if ($line =~ /\$MAIN_PARAM\{"HOSTNM"\} =/) {
        print "Find hostname declaration.\n";
        print $script_out_fh '$MAIN_PARAM{"HOSTNM"} = "此处填写数据库节点名称";' . "\n";
    }
    elsif ($line =~ /\$MAIN_PARAM\{"USERNM"\} =/) {
        print "Find user name declaration.\n";
        print $script_out_fh '$MAIN_PARAM{"USERNM"} = "此处填写数据库用户名称";' . "\n";
    }
    elsif ($line =~ /\$MAIN_PARAM\{"PASSWD"\} =/) {
        print "Find password declaration.\n";
        print $script_out_fh '$MAIN_PARAM{"PASSWD"} = "此处填写数据库用户口令";' . "\n";
    }
    elsif ($line =~ /\$MAIN_PARAM\{'CMSSDB'\} =/) {
        print "Find cmss db declaration.\n";
        print $script_out_fh '$MAIN_PARAM{"CMSSDB"} = "WXHDATA";' . "\n";
    }
    elsif ($line =~ /\$MAIN_PARAM\{'TEMP_DB'\} =/) {
        print "Find temp db declaration.\n";
        print $script_out_fh '$MAIN_PARAM{"TEMP_DB"} = "WXHDATA";' . "\n";
    }
    else {
        print $script_out_fh $line;
    }
}

close($script_fh);
close($script_out_fh);

rename("$release_dir/abno_incm.pl.new", "$release_dir/abno_incm.pl");

chdir('target');

my $zip = Archive::Zip::Archive->new();

$zip->addTree("release-$time", "release-$time");
die "Save zip file failed." unless ($zip->writeToFileNamed("abno-$time.zip") == AZ_OK);
