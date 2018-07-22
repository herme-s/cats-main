use strict;
use warnings;

package CATS::Form;

use CATS::DB;
use CATS::Globals qw($t);
use CATS::Messages qw(msg res_str);
use CATS::Output qw(init_template url_f);
use CATS::Web qw(param url_param);

use Exporter qw(import);

our @EXPORT = qw(
    validate_string_length
    validate_integer
);

sub new {
    my ($class, $self) = @_;
    $self->{table} or die 'No table';
    $self->{fields} or die 'No fields';
    $self->{edit_param} ||= 'edit';
    for (@{$self->{fields}}) {
        $_->{name} or die;
    }
    bless $self, $class;
}

sub field_names { sort map $_->{name}, @{$_[0]->{fields}} }

# Params: opts { after, href_action_params }
sub edit_frame {
    my ($self, $p, %opts) = @_;
    $p or die 'No params';
    init_template($p, $self->{templates}->{edit_frame} || die 'No edit frame template');

    my $id = $p->{$self->{edit_param}} // url_param($self->{edit_param});

    my $field_values = $id ? CATS::DB::select_row(
        $self->{table}, [ $self->field_names ], { id => $id }) : {};
    $field_values->{id} //= $id;
    $opts{after}->($field_values) if $opts{after};

    $self->{href_action} or die 'No href_action';
    $t->param(
        id => $id,
        %$field_values,
        href_action => url_f($self->{href_action}, @{$opts{href_action_params} || []}),
    );
}

# Params: opts { before }
sub edit_save {
    my ($self, $p, %opts) = @_;
    $p or die 'No params';
    my $params;
    $params->{$_} = $p->{$_} // param($_) for $self->field_names;
    $opts{before}->($params) if $opts{before};
    $p->{id} //= param('id');

    my ($stmt, @bind) = $p->{id} ?
        $sql->update($self->{table}, $params, { id => $p->{id} }) :
        $sql->insert($self->{table}, { %$params, id => ($p->{id} = new_id) });
    warn "$stmt\n@bind" if $self->{debug};
    $dbh->do($stmt, undef, @bind);
    $dbh->commit;
    1;
}

# Params: opts { id, descr, msg, before_commit }
sub edit_delete {
    my ($self, %opts) = @_;
    $opts{id} or return;
    $opts{descr} //= 1;
    if (my ($descr) = $dbh->selectrow_array(_u $sql->select(
        $self->{table}, [ $opts{descr} ], { id => $opts{id} }))
    ) {
        $dbh->do(_u $sql->delete($self->{table}, { id => $opts{id} }));
        $opts{before_commit}->() if $opts{before_commit};
        $dbh->commit;
        msg($opts{msg}, $descr) if $opts{msg};
    }
}

sub validate_string_length {
    my ($str, $field_name_id, $min, $max) = @_;
    $str //= '';
    return 1 if $min <= length($str) && length($str) <= $max;
    my $fn = res_str($field_name_id);
    $min ? msg(1044, $fn, $min, $max) : msg(1043, $fn, $max);
}

# Params: p { allow_empty, min, max }
sub validate_integer {
    my ($str, $field_name_id, %p) = @_;
    defined $p{min} && defined $p{max} or die;
    if ($str) {
        return 1 if $str =~ /^\d+$/ && $p{min} <= $str && $str <= $p{max};
    }
    elsif ($p{allow_empty}) {
        return 1;
    }
    msg(1045, res_str($field_name_id), $p{min}, $p{max});
}

package CATS::Field;

use Encode;

use CATS::Messages qw(msg res_str);

sub new {
    my ($class, %r) = @_;
    bless my $self = {}, $class;
    $self->{name} = $r{name} or die;
    $self->{db_name} = $r{db_name} || $r{name};
    $self->{caption} = $r{caption} || $r{name};
    $self->{validators} = $r{validators} // [];
    ref $self->{validators} eq 'ARRAY' or $self->{validators} = [ $self->{validators} ];
    $self->{$_} = $r{$_} for qw(after_load before_save editor);
    $self;
}

sub web_data {
    my ($self, $value, $error) = @_;
    { field => $self, value => $value, error => $error, caption => $self->caption_res };
}

sub caption_res { $_[0]->{caption} =~ /^\d+$/ ? res_str($_[0]->{caption}) : '' }

sub parse_web_param {
    my ($self, $p) = @_;
    my $value = Encode::decode_utf8($p->{$self->{name}} // '');
    $self->web_data($value, $self->validate($value));
}

sub validate {
    my ($self, $value) = @_;
    for my $v (@{$self->{validators}}) {
        if (ref $v eq 'CODE') {
            my $error = $v->($value, $self);
            return $error if $error;
        }
        elsif ($value !~ $v) {
            return 'Wrong format';
        }
    }
}

sub load {
    my ($self, $value) = @_;
    $self->{after_load} ? $self->{after_load}->($value) : $value;
}

sub save {
    my ($self, $value) = @_;
    $self->{before_save} ? $self->{before_save}->($value) : $value;
}

sub str_length {
    my ($min, $max) = @_;
    sub {
        my ($value, $field) = @_;
        $value //= '';
        return if $min <= length($value) && length($value) <= $max;
        my $fn = $field->caption_res;
        $min ? res_str(1044, $fn, $min, $max) : res_str(1043, $fn, $max);
    };
}

# Params:{ allow_empty, min, max }
sub int_range {
    my (%opts) = @_;
    defined $opts{min} && defined $opts{max} or die;
    sub {
        my ($value, $field) = @_;
        if (($value // '') ne '') {
            return if $value =~ /^\d+$/ && $opts{min} <= $value && $value <= $opts{max};
        }
        elsif ($opts{allow_empty}) {
            return;
        }
        res_str(1045, $field->caption_res, $opts{min}, $opts{max});
    };
}

package CATS::Form1;

use CATS::DB;
use CATS::Globals qw($t);
use CATS::Messages qw(msg);
use CATS::Output qw(init_template url_f);
use CATS::RouteParser;

use Exporter qw(import);

our @EXPORT = qw(int_range str_length);

sub new {
    my ($class, %r) = @_;
    bless my $self = {}, $class;

    $self->{$_} = $r{$_} or die "No $_" for qw(table href_action);
    $r{fields} or die 'No fields';
    $self->{fields} = [ map ref $_ eq 'CATS::Field' ? $_ : CATS::Field->new(@$_), @{$r{fields}} ];
    $self->{sql_fields} = [ map $_->{db_name}, $self->fields ];
    $self->{id_param} = $r{id_param} // 'id';
    $self->{template_var} = $r{template_var} // 'form_data';
    $self->{descr_field} = $r{descr_field} // 'id';
    $self->{validators} = $r{validators} // [];
    $self->{$_} = $r{$_} for qw(after_load before_commit before_save debug msg_deleted msg_saved);
    $self;
}

sub fields { @{$_[0]->{fields}} }

sub load {
    my ($self, $id) = @_;
    my @db_data = $dbh->selectrow_array(_u $sql->select(
        $self->{table}, $self->{sql_fields}, { id => $id }));
    my $i = 0;
    my $data = [ map +$_->load($db_data[$i++]), $self->fields ];
    $self->{after_load}->($data) if $self->{after_load};
    $data;
}

sub save {
    my ($self, $id, $data, %opts) = @_;
    $self->{before_save}->($data) if $self->{before_save};
    my $i = 0;
    my %db_data = map { $_->{db_name} => $_->save($data->[$i++]) } $self->fields;
    my ($stmt, @bind) = $id ?
        $sql->update($self->{table}, \%db_data, { id => $id }) :
        $sql->insert($self->{table}, { %db_data, id => ($id = new_id) });
    warn "$stmt\n@bind" if $self->{debug} || $opts{debug};
    $dbh->do($stmt, undef, @bind);
    if ($opts{commit}) {
        $self->{before_commit}->($self) if $self->{before_commit};
        $dbh->commit;
    }
    $id;
}

sub make {
    my ($self) = @_;
    [ map '', $self->fields ];
}

sub route {
    my ($self) = @_;
    # Validation is performed after routing.
    (id => integer, edit_save => bool, edit_cancel => bool, map { $_->{name} => undef } $self->fields);
}

sub parse_params {
    my ($self, $p) = @_;
    [ map $_->parse_web_param($p), $self->fields ];
}

sub _set_form_data {
    my ($form_data, $ordered) = @_;
    $form_data->{ordered} = $ordered;
    $form_data->{indexed} = { map { $_->{field}->{name} => $_ } @$ordered };
}

sub _redirect {
    my ($p, $redirect, @params) = @_;
    $p->redirect(url_f @$redirect, @params) if $redirect;
}

sub validate {
    my ($self, $form_data, $id) = @_;
    for (@{$self->{validators}}) {
        $_->($form_data, id => $id, form => $self) or return;
    }
    1;
}

# Params: opts { href_action_params, readonly, redirect }
sub edit_frame {
    my ($self, $p, %opts) = @_;

    return _redirect($p, $opts{redirect}) if $p->{edit_cancel};

    my $id = $p->{$self->{id_param}};
    my $form_data = {
        form => $self,
        readonly => $opts{readonly},
        $self->{id_param} => $id,
        href_action => url_f($self->{href_action},
            $self->{id_param} => $id, @{$opts{href_action_params} || []}),
    };
    $t->param($self->{template_var} => $form_data);
    if ($p->{edit_save} && !$opts{readonly}) {
        _set_form_data($form_data, my $data = $self->parse_params($p));
        return if grep $_->{error}, @$data;
        $self->validate($form_data, $id) or return;
        $id = $self->save($id, [ map $_->{value}, @$data ], commit => 1);
        my $descr = $form_data->{indexed}->{$self->{descr_field}}->{value};
        _redirect($p, $opts{redirect}, saved => $id);
    }
    else {
        my $data = $id ? $self->load($id) : $self->make;
        my $i = 0;
        _set_form_data($form_data, [ map $_->web_data($data->[$i++]), $self->fields ]);
    }
}

# Params: opts { before_commit }
sub delete_or_saved {
    my ($self, $p, %opts) = @_;
    my $id = $p->{delete} || $p->{saved} or return;
    my ($descr) = $dbh->selectrow_array(_u $sql->select(
        $self->{table}, $self->{descr_field}, { id => $id })) or return;
    if ($p->{delete}) {
        $dbh->do(_u $sql->delete($self->{table}, { id => $id }));
        $opts{before_commit}->($self) if $opts{before_commit};
        $dbh->commit;
        msg($self->{msg_deleted}, $descr) if $self->{msg_deleted};
    }
    if ($p->{saved}) {
        msg($self->{msg_saved}, $descr) if $self->{msg_saved};
    }
}
