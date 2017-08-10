package CATS::Messages;

use strict;
use warnings;

use Exporter qw(import);

our @EXPORT_OK = qw(msg res_str);

use Carp qw(croak);

use CATS::Config qw(cats_dir);
use CATS::Constants;
use CATS::Globals qw($t);
use CATS::Settings;
use CATS::Web qw(param);

my $messages;

sub init_messages_lang {
    my ($lang) = @_;
    my $msg_file = cats_dir() . "../tt/lang/$lang/strings";

    my $r = [];
    open my $f, '<', $msg_file or die "Couldn't open message file: '$msg_file'.";
    binmode($f, ':utf8');
    while (my $line = <$f>) {
        $line =~ m/^(\d+)\s+\"(.*)\"\s*$/ or next;
        $r->[$1] and die "Duplicate message id: $1";
        $r->[$1] = $2;
    }
    $r;
}

# Preserve messages between http requests.
sub init { $messages //= { map { $_ => init_messages_lang($_) } @cats::langs }; }

sub res_str {
    my ($id, @params) = @_;
    my $s = $messages->{CATS::Settings::lang()}->[$id] or die "Unknown res_str id: $id";
    sprintf($s, @params);
}

sub msg {
    defined $t or croak q~Call to 'msg' before 'init_template'~;
    $t->param(message => res_str(@_));
    undef;
}

sub problem_status_names() {+{
    $cats::problem_st_manual    => res_str(700),
    $cats::problem_st_ready     => res_str(701),
    $cats::problem_st_compile   => res_str(705),
    $cats::problem_st_suspended => res_str(702),
    $cats::problem_st_disabled  => res_str(703),
    $cats::problem_st_hidden    => res_str(704),
}}

1;
