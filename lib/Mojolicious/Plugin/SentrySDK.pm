package Mojolicious::Plugin::SentrySDK;
use Mojo::Base 'Mojolicious::Plugin', -signatures;

use Mojolicious;
use List::Util qw(pairgrep);
use Sentry::SDK;
use Sentry::Util qw(stringify_ref);
use Try::Tiny;

sub register ($self, $app, $conf) {
  $app->hook(
    before_server_start => sub ($server, $app) {
      Sentry::SDK->init($conf);
    }
  );

  $app->hook(
    around_action => sub ($next, $c, $action, $last) {
      return $next->() unless $last;

      my $req = $c->req;

      Sentry::Hub->get_current_hub()->with_scope(sub ($scope) {
        my %cookies = map { ($_->name, $_->value) } ($req->cookies // [])->@*;
        my $transaction_name = $c->match->endpoint->to_string || '/';
        $scope->set_transaction_name($transaction_name);
        my $transaction = Sentry::SDK->start_transaction(
          {
            name    => $transaction_name,
            op      => 'http.server',
            request => {
              url          => $req->url->to_abs->to_string,
              cookies      => \%cookies,
              method       => $req->method,
              query_string => $req->url->query->to_hash,
              headers      => $req->headers->to_hash,
              env          => \%ENV,
            },
          },
        );
        $scope->set_span($transaction);

        $scope->add_event_processor(
          sub ($event, $hint) {
            my $modules = $event->{modules} //= {};
            $modules->{Mojolicious} = $Mojolicious::VERSION;

            $event->{extra}->{session} = stringify_ref($c->session);
            my %stash = pairgrep { $a !~ /^mojo\./ } $c->stash->%*;
            $event->{extra}->{stash} = stringify_ref(\%stash);

            return $event;
          }
        );

        try {
          $next->();
        } catch {
          Sentry::SDK->capture_exception($_, { logger => 'mojo' });
          $c->reply->exception($_)
        } finally {
          my $status = $c->res->code;
          $transaction->set_http_status($status) if $status;
          $transaction->finish();
        };
      });
    }
  );

  $app->hook(
    before_render => sub ($c, $args) {
      return if $args->{'mojo.string'};
      my ($pkg, $file, $line) = caller 2;
      my %data = (
        $args->%{qw(template format handler layout extends inline json text mojo.rendered mojo.maybe)},
        data => $args->{data} && '[...]',
      );
      delete $data{$_} for grep { !$data{$_} } keys %data;
      Sentry::SDK->add_breadcrumb({
          category => 'mojo',
          level => Sentry::Severity->Info,
          message => "Rendering response in $pkg ($file:$line)",
          data => \%data,
        });
    }
  );
}

1;

=encoding utf8

=head1 NAME

Mojolicious::Plugin::SentrySDK - Sentry plugin for Mojolicious

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 OPTIONS

=head2 register

  my $config = $plugin->register(Mojolicious->new);
  my $config = $plugin->register(Mojolicious->new, \%options);

Register Sentry in L<Mojolicious> application.

=head1 SEE ALSO

L<Sentry::SDK>.

=cut
