#!perl

use 5.010;
use strict;
use warnings;

use FindBin '$Bin';
use lib $Bin, "$Bin/t";

use File::Slurp;
use Test::More 0.96;
require "testlib.pl";

test_export_html(
    name => 'export example.org',
    args => {
        source_file=>"$Bin/data/example.org",
        html_title => 'Example',
    },
    status => 200,
    result => scalar read_file("$Bin/data/example.org.html"),
);

done_testing();
