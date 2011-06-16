package Org::Export::Role;
# ABSTRACT: Role for Org exporters

use 5.010;
use strict;
use warnings;
use Log::Any '$log';

use Moo::Role;
use String::Escape qw/elide printable/;

requires 'export_document';
requires 'export_block';
requires 'export_short_example';
requires 'export_comment';
requires 'export_drawer';
requires 'export_footnote';
requires 'export_headline';
requires 'export_list';
requires 'export_list_item';
requires 'export_radio_target';
requires 'export_setting';
requires 'export_table';
requires 'export_table_row';
requires 'export_table_cell';
requires 'export_table_vline';
requires 'export_target';
requires 'export_text';
requires 'export_time_range';
requires 'export_timestamp';
requires 'export_link';

1;
