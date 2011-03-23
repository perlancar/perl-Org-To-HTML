package Org::Export::HTML;
# ABSTRACT: Export Org document to HTML

use 5.010;
use strict;
use warnings;
use Log::Any '$log';

use vars qw($VERSION);

use File::Slurp;
use List::Util;
use Org::Document qw/first/;
use String::Escape qw/elide printable/;

require Exporter;
our @ISA       = qw(Exporter);
our @EXPORT_OK = qw(export_org_to_html);

our %SPEC;
$SPEC{export_org_to_html} = {
    summary => 'Export Org document to HTML',
    args => {
        source_file => ['str' => {
            summary => 'Source Org file to export',
        }],
        source_str => ['str' => {
            summary => 'Alternatively you can specify Org string directly',
        }],
        target_file => ['str' => {
            summary => 'HTML file to write to',
            description => <<'_',

If not specified, HTML string will be returned.

_
        }],
        include_tags => ['array' => {
            of => 'str*',
            summary => 'Include trees that carry one of these tags',
            description => <<'_',

Works like Org's 'org-export-select-tags' variable. If the whole document
doesn't have any of these tags, then the whole document will be exported.
Otherwise, trees that do not carry one of these tags will be excluded. If a
selected tree is a subtree, the heading hierarchy above it will also be selected
for export, but not the text below those headings.

_
        }],
        exclude_tags => ['array' => {
            of => 'str*',
            summary => 'Exclude trees that carry one of these tags',
            description => <<'_',

After 'include_tags' is evaluated, all subtrees that are marked by any of the
exclude tags will be removed from export.

_
        }],
        html_title => ['str' => {
            summary => 'HTML document title, defaults to source_file',
        }],
    }
};
sub export_org_to_html {
    my %args = @_;

    my $doc;
    if ($args{source_file}) {
        $doc = Org::Document->new(from_string =>
                                      scalar read_file($args{source_file}));
    } elsif (defined($args{source_str})) {
        $doc = Org::Document->new(from_string => $args{source_str});
    } else {
        return [400, "Please specify source_file/source_str"];
    }

    my $opts = {};

    my $include_tags = $args{include_tags};
    if ($include_tags) {
        my $doc_has_include_tags;
        for my $h ($doc->find('Org::Element::Headline')) {
            my @htags = $h->get_tags;
            if (defined(first {$_ ~~ @htags} @$include_tags)) {
                $doc_has_include_tags++;
                last;
            }
        }
        $include_tags = undef unless $doc_has_include_tags;
    }
    $opts->{include_tags} = $include_tags;

    $opts->{exclude_tags} = $args{exclude_tags};

    my $html = [];
    push @$html, "<HTML>\n";
    push @$html, (
        "<!-- Generated by ".__PACKAGE__,
        " version ".($VERSION // "?"),
        $args{source_file} ? " from $args{source_file}" : "",
        " on ".scalar(localtime)." -->\n\n");

    push @$html, "<HEAD>\n";
    my $title = $args{html_title} // $args{source_file} // "(no title)";
    push @$html, "<TITLE>", $title, "</TITLE>\n";
    push @$html, "</HEAD>\n\n";

    push @$html, "<BODY>\n";
    _export_elems($html, $opts, $doc);
    push @$html, "</BODY>\n\n";
    push @$html, "</HTML>\n";

    #$log->tracef("html = %s", $html);
    $html = join("", @$html);
    if ($args{target_file}) {
        write_file($args{target_file}, $html);
        return [200, "OK"];
    } else {
        return [200, "OK", $html];
    }
}

sub _export_elems {
    my ($html, $opts, @elems) = @_;

  ELEM:
    for my $el (@elems) {
        $log->tracef("exporting element %s (%s) ...", ref($el),
                     elide(printable($el->as_string), 30));
        my $elc = ref($el);

        my @children;
        @children = @{ $el->children } if $el->children;

        if ($elc eq 'Org::Element::Block') {

            # currently all assumed to be <PRE>
            push @$html, "<PRE>", $el->raw_content, "</PRE>\n\n";

        } elsif ($elc eq 'Org::Element::Comment') {

            push @$html, "<!-- ", $el->_str, " -->\n";

        } elsif ($elc eq 'Org::Element::Drawer') {

            # currently not exported

        } elsif ($elc eq 'Org::Element::Footnote') {

            # currently not exported

        } elsif ($elc eq 'Org::Element::Headline') {

            my @htags = $el->get_tags;
            if ($opts->{include_tags}) {
                if (!defined(first {$_ ~~ @htags} @{$opts->{include_tags}})) {
                    # headline doesn't contain include_tags, select only
                    # suheadlines that contain them
                    @children = ();
                    for my $c (@{ $el->children // []}) {
                        next unless $c->isa('Org::Element::Headline');
                        my @hl_included = $el->find(
                            sub {
                                my $el = shift;
                                return unless
                                    $el->isa('Org::Element::Headline');
                                my @t = $el->get_tags;
                                return defined(first {$_ ~~ @t}
                                                   @{ $opts->{include_tags} });
                            });
                        next unless @hl_included;
                        push @children, $c;
                    }
                    next ELEM unless @children;
                }
            }
            if ($opts->{exclude_tags}) {
                next ELEM if defined(first {$_ ~~ @htags}
                                         @{$opts->{exclude_tags}});
            }

            push @$html, "<H" , $el->level, ">";
            _export_elems($html, $opts, $el->title);
            push @$html, "</H", $el->level, ">\n\n";
            _export_elems($html, $opts, @children);

        } elsif ($elc eq 'Org::Element::List') {

            my $tag;
            my $type = $el->type;
            if    ($type eq 'D') { $tag = 'DL' }
            elsif ($type eq 'O') { $tag = 'OL' }
            elsif ($type eq 'U') { $tag = 'UL' }
            push @$html, "<$tag>\n";
            _export_elems($html, $opts, @children);
            push @$html, "</$tag>\n\n";

        } elsif ($elc eq 'Org::Element::ListItem') {

            if ($el->desc_term) {
                push @$html, "<DT>";
            } else {
                push @$html, "<LI>";
            }

            if ($el->check_state) {
                push @$html, "<STRONG>[", $el->check_state, "]</STRONG>";
            }

            if ($el->desc_term) {
                _export_elems($html, $opts, $el->desc_term);
                push @$html, "</DT>";
                push @$html, "<DD>";
            }

            _export_elems($html, $opts, @children);

            if ($el->desc_term) {
                push @$html, "</DD>\n";
            } else {
                push @$html, "</LI>\n";
            }

        } elsif ($elc eq 'Org::Element::RadioTarget') {

            # currently not exported

        } elsif ($elc eq 'Org::Element::Setting') {

            # currently not exported

        } elsif ($elc eq 'Org::Element::Table') {

            push @$html, "<TABLE BORDER>\n";
            _export_elems($html, $opts, @children);
            push @$html, "</TABLE>\n\n";

        } elsif ($elc eq 'Org::Element::TableCell') {

            push @$html, "<TD>";
            _export_elems($html, $opts, @children);
            push @$html, "</TD>";

        } elsif ($elc eq 'Org::Element::TableRow') {

            push @$html, "<TR>";
            _export_elems($html, $opts, @children);
            push @$html, "</TR>\n";

        } elsif ($elc eq 'Org::Element::TableVLine') {

            # currently not exported

        } elsif ($elc eq 'Org::Element::Target') {

            push @$html, "<A NAME=\"", _escape_target($el->target), "\">";

        } elsif ($elc eq 'Org::Element::Text') {

            my $style = $el->style;
            my $tag;
            if    ($style eq 'B') { $tag = 'B' }
            elsif ($style eq 'I') { $tag = 'I' }
            elsif ($style eq 'U') { $tag = 'U' }
            elsif ($style eq 'S') { $tag = 'STRIKE' }
            elsif ($style eq 'C') { $tag = 'CODE' }
            elsif ($style eq 'V') { $tag = 'TT' }

            push @$html, "<$tag>" if $tag;
            my $text = $el->text;
            $text =~ s/\R\R/\n\n<p>\n\n/g;
            push @$html, $text;
            _export_elems($html, $opts, @children);
            push @$html, "</$tag>" if $tag;

        } elsif ($elc eq 'Org::Element::Link') {

            push @$html, "<A HREF=\"";
            if ($el->link =~ m!^\w+:!) {
                # looks like a url
                push @$html, $el->link;
            } else {
                # assume it's an anchor
                push @$html, "#", _escape_target($el->link);
            }
            push @$html, "\">";
            if ($el->description) {
                _export_elems($html, $opts, $el->description);
            } else {
                push @$html, $el->link;
            }
            push @$html, "</A>";

        } elsif ($elc eq 'Org::Element::TimeRange') {

            push @$html, $el->as_string;

        } elsif ($elc eq 'Org::Element::Timestamp') {

            push @$html, $el->as_string;

        } else {

            _export_elems($html, $opts, @children);

        }

    }
}

sub _escape_target {
    my $target = shift;
    $target =~ s/[^\w]+/_/g;
    $target;
}

1;
__END__

=head1 SYNOPSIS

 use Org::Export::HTML qw(export_org_to_html);

 export_org_to_html(
     source_file  => 'todo.org', # or source_str
     target_file  => 'todo.html',
     html_title   => 'My Todo List',
     include_tags => [...],
     exclude_tags => [...],
 );


=head1 DESCRIPTION

Export Org format to HTML. Currently very barebones; this module is more of a
proof-of-concept for L<Org::Parser>. For any serious exporting, currently you're
better-off using Emacs' org-mode HTML export facility.

This module uses L<Log::Any> logging framework.


=head1 FUNCTIONS

None is exported by default, but they can be.


=head1 SEE ALSO

L<Org::Parser>

=cut
