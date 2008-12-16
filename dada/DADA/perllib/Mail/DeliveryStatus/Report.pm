package Mail::DeliveryStatus::Report;

use Mail::Header;
use strict;
use vars qw(@ISA);
BEGIN { @ISA = qw(Mail::Header) };

# i just don't like how Mail::Header leaves a \n at the end of everything
# meng

sub get {
  my $string = $_[0]->SUPER::get($_[1]);
  $string = q{} unless defined $string and length $string;
  chomp $string;
  return $string;
}

1;
