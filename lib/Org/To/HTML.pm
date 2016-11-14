package Org::To::HTML;

# DATE
# VERSION

use 5.010;
use Log::Any::IfLOG '$log';

use vars qw($VERSION);

use File::Slurper qw(read_text);
use HTML::Entities qw/encode_entities/;
use Org::Document;

use Moo;
use experimental 'smartmatch';
with 'Org::To::Role';
extends 'Org::To::Base';

require Exporter;
our @ISA;
push @ISA,       qw(Exporter);
our @EXPORT_OK = qw(org_to_html);

has naked => (is => 'rw');
has html_title => (is => 'rw');
has css_url => (is => 'rw');

our %SPEC;
$SPEC{org_to_html} = {
    v => 1.1,
    summary => 'Export Org document to HTML',
    description => <<'_',

This is the non-OO interface. For more customization, consider subclassing
Org::To::HTML.

_
    args => {
        source_file => {
            summary => 'Source Org file to export',
            schema => ['str' => {}],
        },
        source_str => {
            summary => 'Alternatively you can specify Org string directly',
            schema => ['str' => {}],
        },
        target_file => {
            summary => 'HTML file to write to',
            schema => ['str' => {}],
            description => <<'_',

If not specified, HTML string will be returned.

_
        },
        include_tags => {
            summary => 'Include trees that carry one of these tags',
            schema => ['array' => {of => 'str*'}],
            description => <<'_',

Works like Org's 'org-export-select-tags' variable. If the whole document
doesn't have any of these tags, then the whole document will be exported.
Otherwise, trees that do not carry one of these tags will be excluded. If a
selected tree is a subtree, the heading hierarchy above it will also be selected
for export, but not the text below those headings.

_
        },
        exclude_tags => {
            summary => 'Exclude trees that carry one of these tags',
            schema => ['array' => {of => 'str*'}],
            description => <<'_',

If the whole document doesn't have any of these tags, then the whole document
will be exported. Otherwise, trees that do not carry one of these tags will be
excluded. If a selected tree is a subtree, the heading hierarchy above it will
also be selected for export, but not the text below those headings.

exclude_tags is evaluated after include_tags.

_
        },
        html_title => {
            summary => 'HTML document title, defaults to source_file',
            schema => ['str' => {}],
        },
        css_url => {
            summary => 'Add a link to CSS document',
            schema => ['str' => {}],
        },
        naked => {
            summary => 'Don\'t wrap exported HTML with HTML/HEAD/BODY elements',
            schema => ['bool' => {}],
        },
        ignore_unknown_settings => {
            schema => 'bool',
        },
    },
};
sub org_to_html {
    my %args = @_;

    my $doc;
    if ($args{source_file}) {
        $doc = Org::Document->new(
            from_string => scalar read_text($args{source_file}),
            ignore_unknown_settings => $args{ignore_unknown_settings},
        );
    } elsif (defined($args{source_str})) {
        $doc = Org::Document->new(from_string => $args{source_str});
    } else {
        return [400, "Please specify source_file/source_str"];
    }

    my $obj = ($args{_class} // __PACKAGE__)->new(
        include_tags => $args{include_tags},
        exclude_tags => $args{exclude_tags},
        css_url      => $args{css_url},
        naked        => $args{naked},
        html_title   => $args{html_title} // $args{source_file},
    );

    my $html = $obj->export($doc);
    #$log->tracef("html = %s", $html);
    if ($args{target_file}) {
        write_file($args{target_file}, $html);
        return [200, "OK"];
    } else {
        return [200, "OK", $html];
    }
}

sub export_document {
    my ($self, $doc) = @_;

    my $html = [];
    unless ($self->naked) {
        push @$html, "<HTML>\n";
        push @$html, (
            "<!-- Generated by ".__PACKAGE__,
            " version ".($VERSION // "?"),
            " on ".scalar(localtime)." -->\n\n");

        push @$html, "<HEAD>\n";
        push @$html, "<TITLE>",
            ($self->html_title // "(no title)"), "</TITLE>\n";
        if ($self->css_url) {
            push @$html, (
                "<LINK REL=\"stylesheet\" TYPE=\"text/css\" HREF=\"",
                $self->css_url, "\" />\n"
            );
        }
        push @$html, "</HEAD>\n\n";

        push @$html, "<BODY>\n";
    }
    push @$html, $self->export_elements(@{$doc->children});
    unless ($self->naked) {
        push @$html, "</BODY>\n\n";
        push @$html, "</HTML>\n";
    }

    join "", @$html;
}

sub export_block {
    my ($self, $elem) = @_;
    # currently all assumed to be <PRE>
    join "", (
        "<PRE CLASS=\"block block_", lc($elem->name), "\">",
        encode_entities($elem->raw_content),
        "</PRE>\n\n"
    );
}

sub export_fixed_width_section {
    my ($self, $elem) = @_;
    join "", (
        "<PRE CLASS=\"fixed_width_section\">",
        encode_entities($elem->text),
        "</PRE>\n"
    );
}

sub export_comment {
    my ($self, $elem) = @_;
    join "", (
        "<!-- ",
        encode_entities($elem->_str),
        " -->\n"
    );
}

sub export_drawer {
    my ($self, $elem) = @_;
    # currently not exported
    '';
}

sub export_footnote {
    my ($self, $elem) = @_;
    # currently not exported
    '';
}

sub export_headline {
    my ($self, $elem) = @_;

    my @children = $self->_included_children($elem);

    join "", (
        "<H" , $elem->level, ">",
        $self->export_elements($elem->title),
        "</H", $elem->level, ">\n\n",
        $self->export_elements(@children)
    );
}

sub export_list {
    my ($self, $elem) = @_;
    my $tag;
    my $type = $elem->type;
    if    ($type eq 'D') { $tag = 'DL' }
    elsif ($type eq 'O') { $tag = 'OL' }
    elsif ($type eq 'U') { $tag = 'UL' }
    join "", (
        "<$tag>\n",
        $self->export_elements(@{$elem->children // []}),
        "</$tag>\n\n"
    );
}

sub export_list_item {
    my ($self, $elem) = @_;

    my $html = [];
    if ($elem->desc_term) {
        push @$html, "<DT>";
    } else {
        push @$html, "<LI>";
    }

    if ($elem->check_state) {
        push @$html, "<STRONG>[", $elem->check_state, "]</STRONG>";
    }

    if ($elem->desc_term) {
        push @$html, $self->export_elements($elem->desc_term);
        push @$html, "</DT>";
        push @$html, "<DD>";
    }

    push @$html, $self->export_elements(@{$elem->children}) if $elem->children;

    if ($elem->desc_term) {
        push @$html, "</DD>\n";
    } else {
        push @$html, "</LI>\n";
    }

    join "", @$html;
}

sub export_radio_target {
    my ($self, $elem) = @_;
    # currently not exported
    '';
}

sub export_setting {
    my ($self, $elem) = @_;
    # currently not exported
    '';
}

sub export_table {
    my ($self, $elem) = @_;
    join "", (
        "<TABLE BORDER>\n",
        $self->export_elements(@{$elem->children // []}),
        "</TABLE>\n\n"
    );
}

sub export_table_row {
    my ($self, $elem) = @_;
    join "", (
        "<TR>",
        $self->export_elements(@{$elem->children // []}),
        "</TR>\n"
    );
}

sub export_table_cell {
    my ($self, $elem) = @_;

    join "", (
        "<TD>",
            $self->export_elements(@{$elem->children // []}),
        "</TD>"
    );
}

sub export_table_vline {
    my ($self, $elem) = @_;
    # currently not exported
    '';
}

sub __escape_target {
    my $target = shift;
    $target =~ s/[^\w]+/_/g;
    $target;
}

sub export_target {
    my ($self, $elem) = @_;
    # target
    join "", (
        "<A NAME=\"", __escape_target($elem->target), "\">"
    );
}

sub export_text {
    my ($self, $elem) = @_;

    my $style = $elem->style;
    my $tag;
    if    ($style eq 'B') { $tag = 'B' }
    elsif ($style eq 'I') { $tag = 'I' }
    elsif ($style eq 'U') { $tag = 'U' }
    elsif ($style eq 'S') { $tag = 'STRIKE' }
    elsif ($style eq 'C') { $tag = 'CODE' }
    elsif ($style eq 'V') { $tag = 'TT' }

    my $html = [];

    push @$html, "<$tag>" if $tag;
    my $text = encode_entities($elem->text);
    $text =~ s/\R\R/\n\n<p>/g;
    $text =~ s/(?<=.)\R/ /g;
    push @$html, $text;
    push @$html, $self->export_elements(@{$elem->children}) if $elem->children;
    push @$html, "</$tag>" if $tag;

    join "", @$html;
}

sub export_time_range {
    my ($self, $elem) = @_;

    $elem->as_string;
}

sub export_timestamp {
    my ($self, $elem) = @_;

    $elem->as_string;
}

sub export_link {
    my ($self, $elem) = @_;

    my $html = [];
    push @$html, "<A HREF=\"";
    if ($elem->link =~ m!^\w+:!) {
        # looks like a url
        push @$html, $elem->link;
    } else {
        # assume it's an anchor
        push @$html, "#", __escape_target($elem->link);
    }
    push @$html, "\">";
    if ($elem->description) {
        push @$html, $self->export_elements($elem->description);
    } else {
        push @$html, $elem->link;
    }
    push @$html, "</A>";

    join "", @$html;
}

1;
# ABSTRACT:

=for Pod::Coverage ^(export_.+)$

=head1 SYNOPSIS

 use Org::To::HTML qw(org_to_html);

 # non-OO interface
 my $res = org_to_html(
     source_file   => 'todo.org', # or source_str
     #target_file  => 'todo.html', # defaults return the HTML in $res->[2]
     #html_title   => 'My Todo List', # defaults to file name
     #include_tags => [...], # default exports all tags.
     #exclude_tags => [...], # behavior mimics emacs's include/exclude rule
     #css_url      => '/path/to/my/style.css', # default none
     #naked        => 0, # if set to 1, no HTML/HEAD/BODY will be output.
 );
 die "Failed" unless $res->[0] == 200;

 # OO interface
 my $oeh = Org::To::HTML->new();
 my $html = $oeh->export($doc); # $doc is Org::Document object


=head1 DESCRIPTION

Export Org format to HTML. To customize, you can subclass this module.

A command-line utility is included: L<org-to-html>.

Note that this module is just a simple exporter, for "serious" works you'll
probably want to use the exporting features or L<org-mode|http://orgmode.org>.


=head1 ATTRIBUTES

=head2 naked => BOOL

If set to true, export_document() will not output HTML/HEAD/BODY wrapping
element. Default is false.

=head2 html_title => STR

Title to use in TITLE element. If unset, defaults to "(no title)" when
exporting.

=head2 css_url => STR

If set, export_document() will output a LINK element pointing to this CSS.


=head1 METHODS

=head1 new(%args)

=head2 $exp->export_document($doc) => HTML

Export document to HTML.


=head1 SEE ALSO

For more information about Org document format, visit http://orgmode.org/

L<Org::Parser>

L<org-to-html>

=cut
