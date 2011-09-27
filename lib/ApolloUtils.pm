# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# the contents of this file are Copyright (c) 2003, 2004, 2005 Daniel Norman
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License as
# published by the Free Software Foundation.
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

package ApolloUtils;

sub new {
      my $pkg = shift;
      my %in = @_;
      my $self = {};
      bless ($self , $pkg);
      $self->{pkg} = $pkg;

      $self->{dbr}    = $in{dbr};
      $self->{logger} = $in{logger};
      $self->{params} = \%in;

      return $self;
};

sub _error {
      my $self = shift;
      my $message = shift;
      my ( $package, $filename, $line, $method) = caller(1);
      if ($self->{logger}){
	    $self->{logger}->logErr($message,$method);
      }else{
	    print STDERR "$message ($method, line $line)\n";
      }
      return undef;
}

sub _mkarrayref{
      my $self = shift;
      my $ref = shift;

      return $self->_error('reference must be defined') unless defined($ref);
      if(ref($ref)){
            return $self->_error('reference is not an arrayref') unless ref($ref) eq 'ARRAY';
            return $ref;
      }else{
            return [$ref];
      }
}

1;
