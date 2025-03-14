package Sentry::Stacktrace;
use Mojo::Base -base, -signatures;

use Sentry::Stacktrace::Frame;

has exception => undef;

has frame_filter => sub {
  sub {0}
};

has frames => sub ($self) { return $self->prepare_frames() };

sub prepare_frames ($self) {
  if (!$self->exception->can('frames')) {
    return [];
  }

  my @frames = reverse map { Sentry::Stacktrace::Frame->from_caller($_->@*) }
    $self->exception->frames->@*;
  _shift_frame_subroutine(@frames);

  return [grep { $self->frame_filter->($_) } @frames];
}

# Shift the subroutine attribute one frame down. `caller` returns the
# subroutine that the frame calls but Sentry expects the subroutine that the
# calling frame called.
sub _shift_frame_subroutine(@frames) {
  my $caller_sub;
  my $caller_args;
  for my $frame (@frames) {
    my $new_caller_sub = $frame->subroutine;
    my $new_caller_args = $frame->vars;
    $frame->subroutine($caller_sub);
    $frame->vars($caller_args);
    $caller_sub = $new_caller_sub;
    $caller_args = $new_caller_args;
  }
}

sub TO_JSON ($self) {
  return { frames => $self->frames };
}

1;
