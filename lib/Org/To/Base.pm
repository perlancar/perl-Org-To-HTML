package Org::To::Base;
# ABSTRACT: Base class for Org exporters

use 5.010;
use Log::Any '$log';

use List::Util qw(first);
use Moo;

=head1 ATTRIBUTES

=head2 include_tags => ARRAYREF

Works like Org's 'org-export-select-tags' variable. If the whole document
doesn't have any of these tags, then the whole document will be exported.
Otherwise, trees that do not carry one of these tags will be excluded. If a
selected tree is a subtree, the heading hierarchy above it will also be selected
for export, but not the text below those headings.

=cut

has include_tags => (is => 'rw');

=head2 exclude_tags => ARRAYREF

If the whole document doesn't have any of these tags, then the whole document
will be exported. Otherwise, trees that do not carry one of these tags will be
excluded. If a selected tree is a subtree, the heading hierarchy above it will
also be selected for export, but not the text below those headings.

exclude_tags is evaluated after include_tags.

=cut

has exclude_tags => (is => 'rw');


=head1 METHODS

=for Pod::Coverage BUILD

=cut

=head2 $exp->export($doc) => STR

Export Org.

=cut

sub export {
    my ($self, $doc) = @_;

    my $inct = $self->include_tags;
    if ($inct) {
        my $doc_has_include_tags;
        for my $h ($doc->find('Org::Element::Headline')) {
            my @htags = $h->get_tags;
            if (defined(first {$_ ~~ @htags} @$inct)) {
                $doc_has_include_tags++;
                last;
            }
        }
        $self->include_tags(undef) unless $doc_has_include_tags;
    }

    $self->export_elements($doc);
}

=head2 $exp->export_elements(@elems) => STR

Export Org element objects and with the children, recursively. Will call various
export_*() methods according to element class. Should return a string which is
the exported document.

=cut

sub export_elements {
    my ($self, @elems) = @_;

    my $res = [];
  ELEM:
    for my $elem (@elems) {
        if ($log->is_trace) {
            $log->tracef("exporting element %s (%s) ...", ref($elem),
                         elide(printable($elem->as_string), 30));
        }
        my $elc = ref($elem);

        if ($elc eq 'Org::Element::Block') {
            push @$res, $self->export_block($elem);
        } elsif ($elc eq 'Org::Element::FixedWidthSection') {
            push @$res, $self->export_fixed_width_section($elem);
        } elsif ($elc eq 'Org::Element::Comment') {
            push @$res, $self->export_comment($elem);
        } elsif ($elc eq 'Org::Element::Drawer') {
            push @$res, $self->export_drawer($elem);
        } elsif ($elc eq 'Org::Element::Footnote') {
            push @$res, $self->export_footnote($elem);
        } elsif ($elc eq 'Org::Element::Headline') {
            push @$res, $self->export_headline($elem);
        } elsif ($elc eq 'Org::Element::List') {
            push @$res, $self->export_list($elem);
        } elsif ($elc eq 'Org::Element::ListItem') {
            push @$res, $self->export_list_item($elem);
        } elsif ($elc eq 'Org::Element::RadioTarget') {
            push @$res, $self->export_radio_target($elem);
        } elsif ($elc eq 'Org::Element::Setting') {
            push @$res, $self->export_setting($elem);
        } elsif ($elc eq 'Org::Element::Table') {
            push @$res, $self->export_table($elem);
        } elsif ($elc eq 'Org::Element::TableCell') {
            push @$res, $self->export_table_cell($elem);
        } elsif ($elc eq 'Org::Element::TableRow') {
            push @$res, $self->export_table_row($elem);
        } elsif ($elc eq 'Org::Element::TableVLine') {
            push @$res, $self->export_table_vline($elem);
        } elsif ($elc eq 'Org::Element::Target') {
            push @$res, $self->export_target($elem);
        } elsif ($elc eq 'Org::Element::Text') {
            push @$res, $self->export_text($elem);
        } elsif ($elc eq 'Org::Element::Link') {
            push @$res, $self->export_link($elem);
        } elsif ($elc eq 'Org::Element::TimeRange') {
            push @$res, $self->export_time_range($elem);
        } elsif ($elc eq 'Org::Element::Timestamp') {
            push @$res, $self->export_timestamp($elem);
        } elsif ($elc eq 'Org::Document') {
            push @$res, $self->export_document($elem);
        } else {
            $log->warn("Don't know how to export $elc element, skipped");
            push @$res, $self->export_elements(@{$elem->children})
                if $elem->children;
        }
    }

    join "", @$res;
}

1;
__END__

=head1 SYNOPSIS

 # Not to be used directly. Use one of its subclasses, like Org::To::HTML.


=head1 DESCRIPTION

This module is a base class for Org exporters. To create an exporter, subclass
from this class (as well as add L<Org::To::Role> role) and provide an
implementation for the export_*() methods. Add extra attributes for export
options as necessary (for example, Org::To::HTML adds C<html_title>, C<css_url>,
and so on).


=cut
