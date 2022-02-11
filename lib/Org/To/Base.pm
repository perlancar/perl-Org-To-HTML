package Org::To::Base;

use strict;
use 5.010001;
use Log::ger;

use List::Util qw(first);
use Moo;
use experimental 'smartmatch';

# AUTHORITY
# DATE
# DIST
# VERSION

has source_file => (is => 'rw'); # for informational purposes
has include_tags => (is => 'rw');
has exclude_tags => (is => 'rw');

sub _included_children {
    my ($self, $elem) = @_;

    my @htags = $elem->get_tags;
    my @children = @{$elem->children // []};
    if ($self->include_tags) {
        if (!defined(first {$_ ~~ @htags} @{$self->include_tags})) {
            # headline doesn't contain include_tags, select only
            # suheadlines that contain them
            @children = ();
            for my $c (@{ $elem->children // []}) {
                next unless $c->isa('Org::Element::Headline');
                my @hl_included = $elem->find(
                    sub {
                        my $el = shift;
                        return unless
                            $elem->isa('Org::Element::Headline');
                        my @t = $elem->get_tags;
                        return defined(first {$_ ~~ @t}
                                           @{$self->include_tags});
                    });
                next unless @hl_included;
                push @children, $c;
            }
            return () unless @children;
        }
    }
    if ($self->exclude_tags) {
        return () if defined(first {$_ ~~ @htags}
                                 @{$self->exclude_tags});
    }
    @children;
}

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

sub export_elements {
    my ($self, @elems) = @_;

    my $res = [];
  ELEM:
    for my $elem (@elems) {
        if ($self->can("before_export_element")) {
            $self->before_export_element(
                hook => 'before_export_element',
                elem => $elem,
            );
        }
        if (log_is_trace) {
            require String::Escape;
            log_trace("exporting element %s (%s) ...", ref($elem),
                         String::Escape::elide(
                             String::Escape::printable($elem->as_string), 30));
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
            log_warn("Don't know how to export $elc element, skipped");
            push @$res, $self->export_elements(@{$elem->children})
                if $elem->children;
        }

        if ($self->can("after_export_element")) {
            $self->after_export_element(
                hook => 'after_export_element',
                elem => $elem,
            );
        }
    }

    join "", @$res;
}

1;
# ABSTRACT: Base class for Org exporters

=for Pod::Coverage BUILD

=head1 SYNOPSIS

 # Not to be used directly. Use one of its subclasses, like Org::To::HTML.


=head1 DESCRIPTION

This module is a base class for Org exporters. To create an exporter, subclass
from this class (as well as add L<Org::To::Role> role) and provide an
implementation for the export_*() methods. Add extra attributes for export
options as necessary (for example, Org::To::HTML adds C<html_title>, C<css_url>,
and so on).


=head1 ATTRIBUTES

=head2 include_tags

Arrayref. Works like Org's 'org-export-select-tags' variable. If the whole
document doesn't have any of these tags, then the whole document will be
exported. Otherwise, trees that do not carry one of these tags will be excluded.
If a selected tree is a subtree, the heading hierarchy above it will also be
selected for export, but not the text below those headings.

=head2 exclude_tags

Arrayref. If the whole document doesn't have any of these tags, then the whole
document will be exported. Otherwise, trees that do not carry one of these tags
will be excluded. If a selected tree is a subtree, the heading hierarchy above
it will also be selected for export, but not the text below those headings.

C<exclude_tags> is evaluated after L</include_tags>.

=head2 source_file

String. Optional. Can be set for informational purposes, e.g. will be used as
default title when document does not set C>#+TITLE>.


=head1 METHODS

=head2 $exp->export($doc) => STR

Export Org.

=head2 $exp->export_elements(@elems) => STR

Export Org element objects and with the children, recursively. Will call various
C<export_*()> methods according to element class. Should return a string which
is the exported document.

Several hooks are recognized and will be invoked if defined:

=over

=item * before_export_element

Will be called before calling each C<export_*()>. Will be passed hash argument
C<%hash> containing these keys: C<hook> (hook name, in this case
C<before_export_element>), C<elem> (the element object).

=item * after_export_element

Will be called after calling each C<export_*()>. Will be passed hash argument
C<%hash> containing these keys: C<hook> (hook name, in this case
C<after_export_element>), C<elem> (the element object).

=back
