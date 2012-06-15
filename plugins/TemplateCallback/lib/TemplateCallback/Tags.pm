package TemplateCallback::Tags;
use strict;
use warnings;

# DB storage:
# type => 't_callback', name => 'verytop.entry',(or 'plugin_id::verytop.entry')
# text => '<callback text>', build_interval => <priotiry>
# identifier => 'publish'

sub init_callbacks_from_yaml {
    my ($app, $ctx, $callbacks_listing) = @_;
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
}

sub init_callbacks_from_files {
    my ($app, $ctx, $callbacks_listing) = @_;
    while (my ($plugin_sig, $rec) = each %MT::Plugins) {
        my $plugin = $rec->{object};
        my $id = $plugin->id;
        my $tc_path = File::Spec->catfile( $plugin->path, 'tmpl', 'callbacks' );
        next unless -d $tc_path;
        next unless opendir(my $dh, $tc_path);
        while (my $file = readdir $dh) {
            my ($name, $priority) = $file =~ m/^(.*)\.(\d+)\.tmpl$/;
            next unless $name;
            my $cb_rec = {
                plugin => $plugin,
                name => $name,
                priority => $priority,
                file => File::Spec->catfile($tc_path, $file),
            };
            my $array = ( $callbacks_listing->{$cb_rec->{name}} ||= [] );
            push @$array, $cb_rec;
        }
    }
}

sub init_callbacks_from_db {
    my ($app, $ctx, $callbacks_listing) = @_;

    my $blog = $ctx->stash('blog');
    my $blog_id = 
        !$blog ? undef :
        ref $blog ? $blog->id :
        $blog;

    my $iter = $app->model('template')->load_iter({
        type => 't_callback',
        identifier => 'publish',
        blog_id => ($blog_id ? [0, $blog_id] : 0),
    });
    while (my $tmpl = $iter->()) {
        my $cb_rec = {};
        my $name = $tmpl->name();
        if ($name =~ s/^(\w+::)//) {
            my $plugin = $1;
            # skip callbacks from non-loaded plugins
            next unless $app->component($plugin);
            $cb_rec->{plugin} = $plugin;
        }
        $cb_rec->{priority} = $tmpl->build_interval();
        $cb_rec->{template} = $tmpl->text();
        $cb_rec->{name} = 'publish.' . $name;
        my $array = ( $callbacks_listing->{$cb_rec->{name}} ||= [] );
        push @$array, $cb_rec;
    }
}

sub init_callbacks {
    my ($app, $ctx) = @_;
    my $callbacks_listing = $ctx->stash('callbacks_listing');
    return $callbacks_listing if $callbacks_listing;
    $callbacks_listing = {};

    init_callbacks_from_files($app, $ctx, $callbacks_listing);
    init_callbacks_from_db($app, $ctx, $callbacks_listing);

    $ctx->stash('callbacks_listing', $callbacks_listing);
    return $callbacks_listing;
}

sub get_cb_by_name {
    my ($ctx, $reg, $name_arg) = @_;
    my $name_prefix  = $ctx->var('callback_prefix') || '';
    my $name_postfix = $ctx->var('callback_postfix') || '';
    my $cache_name = "$name_prefix#$name_arg#$name_postfix";
    my $callbacks_cache = $ctx->stash('callbacks_cache');
    if (not $callbacks_cache) {
        $ctx->stash('callbacks_cache', ( $callbacks_cache = {} ) );
    }
    return $callbacks_cache->{$cache_name} if exists $callbacks_cache->{$cache_name};
    my @names = grep $_, split /[\s,]+/, $name_arg;
    my @all_names;
    foreach my $name (@names) {
        $name = "$name_prefix.$name" if $name_prefix;
        $name .= ".$name_postfix" if $name_postfix;
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
    $callbacks_cache->{$cache_name} = \@all_callbacks;
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
    my $reg = init_callbacks($app, $ctx);
    my $name_arg = $args->{name} 
        or return $ctx->error( "Callback name is needed" );
    my $all_callbacks = get_cb_by_name($ctx, $reg, $name_arg);
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
    my $reg = init_callbacks($app, $ctx);
    my $name_arg = $args->{name} 
        or return $ctx->error( "Callback name is needed" );
    my $priority = $args->{priority} || 5;

    my $name_prefix  = $ctx->var('callback_prefix') || '';
    my $name_postfix = $ctx->var('callback_postfix') || '';
    $name_arg = "$name_prefix.$name_arg" if $name_prefix;
    $name_arg .= ".$name_postfix" if $name_postfix;

    my $val = $ctx->stash('tokens');
    return unless defined($val);
    $val = bless $val, 'MT::Template::Tokens';
    my $array = ( $reg->{$name_arg} ||= [] );
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
    my $reg = init_callbacks($app, $ctx);
    my $name_arg = $args->{name} 
        or return $ctx->error( "Callback name is needed" );
    my $all_callbacks = get_cb_by_name($ctx, $reg, $name_arg);
    return scalar(@$all_callbacks);    
}

sub _hdlr_widget_manager {
    my ( $ctx, $args, $cond ) = @_;
    my $cb_name = $args->{callback}
        or return $ctx->super_handler( $args, $cond );
    my $tmpl_name = delete $args->{name}
        or return $ctx->error( MT->translate("name is required.") );
    my $blog_id = $args->{blog_id} || $ctx->{__stash}{blog_id} || 0;

    my $tmpl = MT->model('template')->load(
        {   name    => $tmpl_name,
            blog_id => $blog_id ? [ 0, $blog_id ] : 0,
            type    => 'widgetset'
        },
        {   sort      => 'blog_id',
            direction => 'descend'
        }
        )
        or return $ctx->error(
        MT->translate( "Specified WidgetSet '[_1]' not found.", $tmpl_name )
        );

    my @widgets;
    if ( my $text = $tmpl->text ) {
        @widgets = $text =~ /(<mt:include widget="[^"]*">)/g;
    }

    my $app = MT->instance;
    
    if (@widgets) {
        my $step = 4.0 / scalar(@widgets);
        my $priority = 3;
        my $reg = init_callbacks($app, $ctx);
        my ($i_cb_name) = split(' ', $cb_name);
        my $name_prefix  = $ctx->var('callback_prefix');
        $i_cb_name = "$name_prefix.$i_cb_name" if $name_prefix;
        my $cb_array = ( $reg->{$i_cb_name} ||= [] );
        for my $widget (@widgets) {
            my $cb = {
                template => $widget,
                priority => $priority,
            };
            $priority += $step;
            push @$cb_array, $cb;
        }
    }

    return template_callback($ctx, { name => $cb_name });
}


1;