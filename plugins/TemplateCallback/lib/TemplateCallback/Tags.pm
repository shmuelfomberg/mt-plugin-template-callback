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
    my ($ctx, $reg, $name_arg) = @_;
    return $callbacks_cache->{$name_arg} if exists $callbacks_cache->{$name_arg};
    my $name_prefix  = $ctx->var('callback_prefix');
    my $name_postfix = $ctx->var('callback_postfix');
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
    my $all_callbacks = get_cb_by_name($ctx, $reg, $name_arg);
    return scalar(@$all_callbacks);    
}

sub _hdlr_widget_manager {
    my ( $ctx, $args, $cond ) = @_;
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

    ## Load all widgets for make cache.
    my @widgets;
    if ( my $modulesets = $tmpl->modulesets ) {
        my @widget_ids = split ',', $modulesets;
        my $terms
            = ( scalar @widget_ids ) > 1
            ? { id => \@widget_ids }
            : $widget_ids[0];
        my @objs = MT->model('template')->load($terms);
        my %widgets = map { $_->id => $_ } @objs;
        push @widgets, $widgets{$_} for @widget_ids;
    }
    elsif ( my $text = $tmpl->text ) {
        my @widget_names = $text =~ /widget\=\"([^"]+)\"/g;
        my @objs = MT->model('template')->load(
            {   name    => \@widget_names,
                blog_id => [ $blog_id, 0 ],
            }
        );
        @objs = sort { $a->blog_id <=> $b->blog_id } @objs;
        my %widgets;
        $widgets{ $_->name } = $_ for @objs;
        push @widgets, $widgets{$_} for @widget_names;
    }
    return '' unless scalar @widgets;

    if (not $callbacks_listing) {
        # callback were not initialized until now? probably old-style template
        my @res;
        {
            local $ctx->{__stash}{tag} = 'include';
            for my $widget (@widgets) {
                my $name     = $widget->name;
                my $stash_id = Encode::encode_utf8(
                    join( '::', 'template_widget', $blog_id, $name ) );
                my $req = MT::Request->instance;
                my $tokens = $ctx->stash('builder')->compile( $ctx, $widget );
                $req->stash( $stash_id, [ $widget, $tokens ] );
                my $out = $ctx->invoke_handler( 'include',
                    { %$args, widget => $name, }, $cond, );

                # if error is occured, pass the include's errstr
                return unless defined $out;

                push @res, $out;
            }
        }
        return join( '', @res );
    }
    else {
        my $step = 4.0 / scalar(@widgets);
        my $priority = 3;
        my $app = MT->instance;
        my $reg = init_callbacks($app);
        my $name = 
              $tmpl_name eq $app->translate("3-column layout - Primary Sidebar") ? "sidebar_primary"
            : $tmpl_name eq $app->translate("3-column layout - Secondary Sidebar") ? "sidebar_secondary"
            : "sidebar_primary";
        my $name_prefix  = $ctx->var('callback_prefix');
        $name = "$name_prefix.$name" if $name_prefix;
        my $cb_array = ( $reg->{$name} ||= [] );
        for my $widget (@widgets) {
            my $tokens = $ctx->stash('builder')->compile( $ctx, $widget );
            my $cb = { tokens => $tokens, priority => $priority };
            $priority += $step;
            push @$cb_array, $cb;
        }
        return '';
    }
}


1;