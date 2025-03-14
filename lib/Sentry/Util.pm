package Sentry::Util;
use Mojo::Base -strict, -signatures;

use overload;
use Exporter     qw(import);
use Mojo::Loader qw(load_class);
use Mojo::Util   qw(dumper monkey_patch);
use UUID::Tiny ':std';
use List::Util qw(pairmap);

our @EXPORT_OK = qw(uuid4 truncate merge around restore_original stringify_ref);

sub uuid4 {
  my $uuid = create_uuid_as_string(UUID_V4);
  $uuid =~ s/-//g;
  return $uuid;
}

sub truncate ($string, $max = 0) {
  return $string if (ref($string) || $max == 0);

  return length($string) <= $max ? $string : substr($string, 0, $max) . '...';
}

sub merge ($target, $source, $key) {
  $target->{$key}
    = { ($target->{$key} // {})->%*, ($source->{$key} // {})->%* };
}

my %Patched = ();

sub around ($package, $method, $cb) {
  my $key = $package . '::' . $method;
  return if $Patched{$key};

  if (my $e = load_class $package) {
    die ref $e ? "Exception: $e" : "Module $package not found";
  }

  my $orig = $package->can($method);

  monkey_patch $package, $method => sub { $cb->($orig, @_) };

  $Patched{$key} = $orig;

  return;
}

sub restore_original ($package, $method) {
  my $key  = $package . '::' . $method;
  my $orig = $Patched{$key} or return;
  monkey_patch $package, $method, $orig;
  delete $Patched{$key};
}

sub stringify_ref($val) {
  if (ref $val eq 'HASH') {
    return { pairmap { $a => stringify_ref($b) } %$val };
  } elsif (ref $val eq 'ARRAY') {
    return [ map { stringify_ref($_) } @$val ];
  } elsif (!ref $val) {
    return $val;
  } else {
    ## no critic (Variables::RequireInitializationForLocalVars)
    local $@;
    local $SIG{__DIE__};
    ## use critic

    my $str = eval { $val . q{} };

    return $@ ? overload::AddrRef($val) : $str;
  }
}

1;
