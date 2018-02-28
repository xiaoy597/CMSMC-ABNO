package common_module;
use strict;
use warnings FATAL => 'all';
use base qw(Exporter);

our($VERSION, @ISA, @EXPORT, @EXPORT_OK);

$VERSION   = '1.0';
@EXPORT_OK = qw(passport_decrypt);

# For test.
sub passport_decrypt {
    my ($enc_str) = $@;

    return $enc_str;
}

1;