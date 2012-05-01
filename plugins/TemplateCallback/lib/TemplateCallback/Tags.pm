package TemplateCallback::Tags;
use strict;
use warnings;

my $callbacks_listing;
my $callbacks_cache = {};

sub init_callbacks {
    my $app = shift;
    return $callbacks_listing if $callbacks_listing;
    $callbacks_listing = {};
    while (my ($plugin_sig, $rec) = each %MT::Plugins) {
        my $plugin = $rec->{object};
        my $id = $plugin->id;
        my $data = $plugin->load_registry("tmpl_cb.yaml");
        $data = $data->{callbacks} if $data;
        next unless $data;
        for my $cb_rec (@$data) {
            $cb_rec->{plugin} = $id;
            $cb_rec->{priority} ||= 5;
            my $array = ( $callbacks_listing->{$cb_rec->{name}} ||= [] );
            push @$array, $cb_rec;
        }
    }
    return $callbacks_listing;
}

sub get_cb_by_name {
    my ($reg, $name_arg) = @_;
    return $callbacks_cache->{$name_arg} if exists $callbacks_cache->{$name_arg};
    my @names = grep $_, split /[\s,]+/, $name_arg;
    my @all_names;
    foreach my $name (@names) {
        my ($ass, @parts) = split /\./, $name;
        push @all_names, $ass;
        foreach my $part (@parts) {
            $ass .= "." . $part;
            push @all_names, $ass;
        }
    }
    my @all_callbacks;
    foreach my $name (@all_names) {
        push @all_callbacks, @{ $reg->{$name} } if exists $reg->{$name};
    }
    @all_callbacks = sort { $a->{priority} <=> $b->{priority} } @all_callbacks;
    $callbacks_cache->{$name_arg} = \@all_callbacks;
    return \@all_callbacks;
}

sub get_cb_by_priority {
    my ($all_callbacks, $priority) = @_;
    my ($min, $max);
    if ($priority =~ /^\d+$/) {
        $min = $max = $priority;
    }
    elsif ($priority =~ /^(\d+)\.\.(\d+)$/) {
        $min = $1;
        $max = $2;
    }
    else {
        return [];
    }
    if (not defined $min) {
    }
    return [ grep { $_->{priority} >= $min and $_->{priority} <= $max } @$all_callbacks ];
}

sub template_callback {
    my ($ctx, $args) = @_;
    my $app = MT->instance;
    my $reg = init_callbacks($app);
    my $name_arg = $args->{name} 
        or return $ctx->error( "Callback name is needed" );
    my $all_callbacks = get_cb_by_name($reg, $name_arg);
    my $priority = $args->{priority} || "1..10";
    $all_callbacks = get_cb_by_priority($all_callbacks, $priority);
    my $output = '';
    my $i       = 1;
    my $vars    = $ctx->{__stash}{vars} ||= {};
    foreach my $cb (@$all_callbacks) {
        local $vars->{__first__}   = $i == 1;
        local $vars->{__last__}    = $i == scalar @$all_callbacks;
        local $vars->{__odd__}     = ( $i % 2 ) == 1;
        local $vars->{__even__}    = ( $i % 2 ) == 0;
        local $vars->{__counter__} = $i;
        if ($cb->{file}) {
            my $fargs = { name => $cb->{file}, component => $cb->{plugin} };
            $output .= MT::Template::Tags::System::_include_name($ctx, $fargs)
        }
        elsif ($cb->{template}) {
            my $tmpl = MT::Template->new_string(\$cb->{template});
            # propagate our context
            local $tmpl->{context} = $ctx;
            local $app->{component} = $cb->{plugin};
            my $out = $tmpl->output();
            return $ctx->error( $tmpl->errstr ) unless defined $out;
            $output .= $out;
        }
        elsif ($cb->{tokens}) {
            local $ctx->{__stash}{tokens} = $cb->{tokens};
            my $out = $ctx->slurp();
            return unless defined $out;
            $output .= $out;            
        }
        $i++;
    }
    return $output;
}

sub set_template_callback {
    my ($ctx, $args, $cond) = @_;
    my $app = MT->instance;
    my $reg = init_callbacks($app);
    my $name_arg = $args->{name} 
        or return $ctx->error( "Callback name is needed" );
    my $priority = $args->{priority} || 5;
    my $val = $ctx->stash('tokens');
    return unless defined($val);
    $val = bless $val, 'MT::Template::Tokens';
    my $array = ( $callbacks_listing->{$name_arg} ||= [] );
    my $cb_rec = {
        plugin => undef,
        priority => $priority,
        tokens => $val,
    };
    push @$array, $cb_rec;
    return '';
}

sub are_callbacks_registred {
    my ($ctx, $args, $cond) = @_;
    my $app = MT->instance;
    my $reg = init_callbacks($app);
    my $name_arg = $args->{name} 
        or return $ctx->error( "Callback name is needed" );
    my $all_callbacks = get_cb_by_name($reg, $name_arg);
    return scalar(@$all_callbacks);    
}

1;