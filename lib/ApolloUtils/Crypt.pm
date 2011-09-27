# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# The contents of this file are Copyright (c) 2003, 2004, 2005 Daniel Norman
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License as
# published by the Free Software Foundation.
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

package ApolloUtils::Crypt;

use strict;
use bytes; # no unicode shit
use ApolloUtils;
use Digest::MD5;
use MIME::Base64;
use Crypt::Blowfish;
use Digest::SHA;

our @ISA = qw(ApolloUtils);

sub encrypt{
      my $self = shift;
      my %params = @_;

      return $self->_error('no key specified')  unless defined($params{key});
      return $self->_error('no data specified') unless defined($params{data});
      #print STDERR "ENC " . encode_base64($params{data}) . "\n"; #DEBUG ONLY
      return $self->_error('key error') unless
	my $key = $self->buildkey($params{key});
      my $handle = new Crypt::Blowfish($key);
      $key = 'ABCDEFGHIJKLMNOPQRSTUVWXYZABCDEFGHIJKLMNOPQRSTUVWXYZ1234'; # zap it

      my $len = length($params{data});
      my $cryptdata;
      foreach (unpack("a8"x(($len/8)+(($len % 8)?1:0)), $params{data})) {
	    $cryptdata .= $handle->encrypt($_ . ("\0"x (8 - length($_))));
      }

      if($params{signed}){
	    my $md5sum = Digest::MD5::md5_base64($params{data} . $params{key});
	    return encode_base64($cryptdata,'') . $md5sum;
      }else{
	    return encode_base64($cryptdata,'');
      }

}


sub decrypt{
      my $self = shift;
      my %params = @_;

      use bytes;

      return $self->_error('no key specified') unless defined($params{key});
      return $self->_error('no data specified') unless defined($params{data});

      my $cryptstring = $params{data};
      my $md5sum;
      if($params{signed}){
	    $cryptstring =~ s/(.{22})$//;
	    $md5sum = $1;
      }

      my $cryptdata = decode_base64($cryptstring);

      return $self->_error('key error') unless
	my $key = $self->buildkey($params{key});
      my $handle = new Crypt::Blowfish($key);
      $key = 'ABCDEFGHIJKLMNOPQRSTUVWXYZABCDEFGHIJKLMNOPQRSTUVWXYZ1234'; # zap it

      my $len = length($cryptdata);

      my $outdata;
      map {$outdata .= $handle->decrypt($_)} unpack("a8"x($len/8), $cryptdata);
      $outdata =~ s/\0*$//;

      if($params{signed}){
	    #print STDERR "DEC " . encode_base64($outdata) . "\n"; #DEBUG ONLY
	    my $md5sum2 = Digest::MD5::md5_base64($outdata . $params{key});
	    if ($md5sum ne $md5sum2) {
		  return $self->_error("checksum mismatch! '$md5sum' '$md5sum2'");
	    }
      }

      return $outdata;
}

sub buildkey{
      my $self = shift;
      my $key = shift;

      my $shaobj = new Digest::SHA(512);
      $shaobj->add($key);
      my $digest = $shaobj->digest();

      return substr($digest,0,56);
}

1;
