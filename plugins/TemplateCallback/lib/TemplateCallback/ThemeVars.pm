package TemplateCallback::ThemeVars;
use strict;
use warnings;
use Data::Dumper;

sub import {
    my ( $element, $theme, $obj_to_apply ) = @_;
    return unless $obj_to_apply->datasource eq 'blog';
    my $scope = $obj_to_apply->class . ':' . $obj_to_apply->id;
    my $plugin = MT->component('TemplateCallback');
    my $cnf = $plugin->get_config_obj($scope);
    my $vars = $element->{data};
    my $param = {};
    while (my ($name, $rec) = each %$vars) {
        $rec->{name} = $name;
        $rec->{value} = $rec->{default};
        $param->{$name} = $rec;
    }
    $cnf->data($param);
    $cnf->save();
    return 1;
}

sub info {
    my ( $element, $theme, $blog ) = @_;
    my $data = $element->{data};
    my $count = scalar keys %$data;
    my $plugin = MT->component('TemplateCallback');
    my $str = $plugin->translate( '[_1] theme variables.', $count );
    return sub { return $str; };
}

sub set_appearance {
    my $app   = shift;
    my $blog = $app->blog;
    my $scope = $blog->class . ':' . $blog->id;
    my $plugin = MT->component('TemplateCallback');
    my $cnf = $plugin->get_config_obj($scope);
    my %params;
    my $c_data = $cnf->data();
    if ($app->param('save')) {
        foreach my $key ( $app->param() ) {
            next unless $key =~ m/^var_(.*)$/;
            my $name = $1;
            next unless exists $c_data->{$name};
            my $rec = $c_data->{$name};
            my $value = $app->param($key);
            if ($rec->{type} eq 'color') {
                next unless $value =~ m/^(?:\w+|#[0-9A-F]+)$/;
                $rec->{value} = $value;
            }
        }
        $cnf->data($c_data);
        $cnf->save();
        $params{system_msg} = "Please rebuild";
    }
    $_->{order} ||= 10000 foreach values %$c_data;
    my @recs = sort { $a->{order} <=> $b->{order} } values %$c_data;
    $params{variables} = \@recs;
    return $plugin->load_tmpl('appearance.tmpl', \%params);
}

1;