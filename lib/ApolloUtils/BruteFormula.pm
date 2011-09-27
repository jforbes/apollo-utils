# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# This software is Copyright (c) 2008 Daniel Norman
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License as
# published by the Free Software Foundation.
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# $Id: BruteFormula.pm,v 1.7 2008/08/19 20:56:56 impious Exp $
# $Source: /cvsroot/apollo-handler/apollo-utils/lib/ApolloUtils/BruteFormula.pm,v $
#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

package ApolloUtils::BruteFormula;

use vars qw(@ISA);
use ApolloUtils;
use strict;
@ISA = ('ApolloUtils');


my @OPERATORS = qw'^ * / + -';
my $OPERATORS = join('',map {"\\$_"} @OPERATORS);
my $VARIABLE = '\w+[\w\d ]*'; #one or more word characters followed by zero or more word/digit characters
my $CONSTANT = '\d+(:\.\d+)?'; # Number, optional decimal



sub parse{
      my $self = shift;
      my %params = @_;

      return $self->_error('-formula must be specified') unless $params{-formula};


      return $self->_error('-translate must be specified') unless $params{-translate};

      my $translate = [];
      if(ref($params{-translate}) eq 'HASH'){
	    push @{$translate}, map {     { name => $_, code => $params{-translate}->{$_} }    } keys %{$params{-translate}};
      }elsif(ref($params{-translate}) eq 'ARRAY'){
	    $translate = $params{-translate};
      }else{
	    return $self->_error('-translate must be a HASHREF or an ARRAYREF');
      }

      my %trans_to_code;
      my %trans_to_ident;

      foreach my $tran (@{$translate}){
	    return $self->_error("name is required in -translate node") unless $tran->{name};
	    return $self->_error("code is required in -translate node") unless $tran->{code};
	    $tran->{ident} ||= $tran->{code};

	    $trans_to_code{  $tran->{name} } = $tran->{code};
	    $trans_to_ident{ $tran->{name} } = $tran->{ident};
      }

      my $job = {
		 used_variables => {},
		 trans_to_code  => \%trans_to_code,
		 trans_to_ident => \%trans_to_ident,
		};

      my $parseret;
      eval{
	    return $self->_error('failed to tokenize formula') unless
	      my $tokens = $self->_tokenize($params{-formula});

	    return $self->_error('failed to parse formula') unless
	      $parseret = $self->_parse($job,$tokens);
      };

      if($@){
	    return {status => 0, error => $@};
      }

      return {
	      status => 1,
	      code   => $parseret,
	      var_ident => [keys %{$job->{used_variables}}],
	     };

}

sub validate{
      my $self = shift;
      my %params = @_;

      return $self->_error('-formula must be specified') unless $params{-formula};

      my $trans;
      if($params{-identify_terms}){
	    return $self->_error('-identify_terms must be specified as a hashref') unless ref($params{-identify_terms}) eq 'HASH';
	    $trans = [ map { { name => $_, code => 1, ident => $params{-identify_terms}->{$_} } } keys %{$params{-identify_terms}} ];
      }else{
	    return $self->_error('-valid_terms must be specified as an arrayref') unless $params{-valid_terms} && ref($params{-valid_terms}) eq 'ARRAY';

	    $trans = {};
	    map {$trans->{$_} = 1} @{$params{-valid_terms}};
      }

      return $self->_error('failed to parse formula') unless
	my $ret = $self->parse(
			       -formula   => $params{-formula},
			       -translate => $trans,
			      );


      if ($ret->{status} == 1) {
	    return {
		    status => 1,
		    var_ident => $ret->{var_ident},
		   };
      } else {
	    return {
		    status => $ret->{status},
		    error  => $ret->{error},
		   }
      }


}

sub _tokenize{
      my $self = shift;
      my $formula = shift;

      my $regex = "[$OPERATORS\(\)]";    #[@OPERATORS\(\)]|$CONSTANT|$VARIABLE
      #print STDERR "REGEX: $regex\n";
      my @parts = split(/($regex)/,$formula);

      #print Dumper(\@parts);


      my @tokens;
      my $offset = 0;
      foreach my $part (@parts){
	    my $len = length($part);

	    my $myoffset = $offset;
	    $offset += $len;

	    $part =~ s/^(\s+)//; # strip whitespace from front
	    my $striplen = length($1);

	    $part =~ s/\s+$//; # and the back too

	    my $final_len = length($part);

	    if($final_len){
		  $myoffset += $striplen;
		  push @tokens, [$part,$myoffset,($final_len+$myoffset)];
	    }
      }

      #use Data::Dumper;
      #print Dumper(\@tokens);

      return \@tokens;
}

sub _parse{
      my $self        = shift;
      my $job         = shift;
      my $work        = shift;
      my $tablevel    = shift || 0;
      my $idx         = shift || 0;
      my $limitidx    = shift || scalar(@$work) - 1;

      return $self->_syntax_err("Too much recursion",$idx) if $tablevel > 10;

      #print STDERR "\t"x$tablevel ."BEGIN PARSE $tablevel [$idx,$limitidx] " .  join('',map {$_->[0]} @$work[$idx .. $limitidx]) . "\n";;
      my $code;
      my $first = 1;
      while (($idx <= $limitidx) && (my $element = $work->[$idx])){
	    my $outstring;

	    # Open parenthetical
	    if($element->[0] eq '('){

		  my $closeidx = $self->_findclose($work,$idx+1,$limitidx) || die "Could not find close";

		  #print STDERR "\t"x$tablevel . "Found peren: [$idx,$closeidx] " . join('',map {$_->[0]} @$work[$idx .. $closeidx]) . "\n";

		  $outstring = $self->_parse($job,$work,$tablevel+1,$idx+1,$closeidx-1);

		  $outstring ='('.$outstring . ')';
		  $idx = $closeidx;

	    }else{
		   my $closeidx = $self->_find_expression($work,$tablevel,$idx,$limitidx);

		   #HERE HERE HERE validate expression range

		   #print STDERR "\t"x$tablevel . "Found expression: [$idx,$closeidx] " . join('',map {$_->[0]} @$work[$idx .. $closeidx]) . "\n";

		   $outstring = $self->_process_expression($job,[ @$work[$idx..$closeidx] ],$tablevel, $first?1:2 );
		   $idx = $closeidx;

	    }
	    $code .= $outstring;
	    $first = 0;
	    $idx++;
      }

      return "$code";
}


sub _find_expression{
      my $self        = shift;
      my $work        = shift;
      my $tablevel    = shift;
      my $idx         = shift;
      my $limitidx    = shift;

      #print STDERR "\t"x$tablevel ."SEARCHING for expression [$idx,$limitidx] ". join('',map {$_->[0]} @$work[$idx .. $limitidx]) . "\n";;

      my @exparts;
      while (($idx <= $limitidx) && (my $token = $work->[$idx])) {

	    my ($string,$offset,$endoffset) = @{$token};
	    #print STDERR "\t"x$tablevel . "Found thingus: $string\n";

	    if ($string =~ /[$OPERATORS]|$VARIABLE|$CONSTANT/) {
		  #die "sanity error" ;

		  return $self->_syntax_err("Sanity error",$offset,$endoffset) if $string =~ /[\(\)]/;
		  $idx++;	# have another go at it

	    }elsif($string eq ')'){  # Very important to check this here

		  return $self->_syntax_err("Unmatched ')'",$offset,$endoffset);

	    } else {
		  #print STDERR "\t"x$tablevel . "PAST END OF EXPRESSION: $string\n";
		  last;		# past the end of the expression
	    }
      }
      $idx--; # rewind one
      return $idx;
}

sub _process_expression{
      my $self     = shift;

      my $job       = shift;
      my $tokens    = shift;
      my $tablevel = shift || 0;
      #print STDERR "\t"x$tablevel ."PROCESSING EXPRESSION: '" . join ('',map {$_->[0]} @$tokens) . "'\n";
      my $mode = shift;

      my @outstrings;

      my $firstoffset;
      my $finaloffset;

      my $divflag;
      foreach my $token (@$tokens){
	    my ($string,$offset,$endoffset) = @{$token};
	    $firstoffset = $token->[1] unless defined($firstoffset);
	    $finaloffset = $token->[2];

	    my $outstring;
	    if($mode == 1){
		  if( $string =~ /$CONSTANT/ ){
			if($divflag && ($string == 0) ){
			      return $self->_syntax_error('Cannot divide by zero',$offset,$endoffset);
			}

			$outstring = $string;
		  }elsif($string =~ /$VARIABLE/){
			$outstring .= '(' if $divflag;
			$outstring .= $job->{trans_to_code}->{$string} || return $self->_syntax_err("Bad variable name '$string'",$offset,$endoffset);
			$job->{used_variables}->{  $job->{trans_to_ident}->{$string}  } = 1;
			$outstring .= ' || 1000000000000)' if $divflag; # Evil hack. fix this
		  }else{
			return $self->_syntax_err("Expect variable or constant",$offset,$endoffset);
		  }

		  $divflag = 0;
		  $mode = 2;
	    }elsif($mode == 2){
		  if( $string =~ /[$OPERATORS]/ ){
			$outstring = $string;
			if($string eq '/'){
			      $divflag = 1;
			}
		  }else{
			$self->_syntax_err("Expect operator",$offset,$endoffset);
		  }

		  $mode = 1;
	    }else{
		  $self->_syntax_err("Invalid mode",$offset,$endoffset);
	    }
	    push @outstrings, $outstring;
      }

      if($mode != 2){
	    $self->_syntax_err("Invalid expression",$firstoffset,$finaloffset);
      }

      return join('',@outstrings);
}

sub _findclose{
      my $self     = shift;
      my $work     = shift;
      my $startidx = my $idx = shift;
      my $limitidx    = shift;

      my $opencount = 1; # start with one ( open against the count
      #my $end=0;
      my $closeidx = 0;
      my $firstoffset;
      my $finaloffset;
      while (!$closeidx && ($idx <= $limitidx) && (my $element = $work->[$idx])){

	    $firstoffset = $element->[1] unless defined($firstoffset);
	    $finaloffset = $element->[2];

	    if ($element->[0] eq ')') {
		  $opencount--;
	    } elsif ($element->[0] eq '(') {
		  $opencount++;
	    }
	    if ($opencount == 0) {
		  $closeidx = $idx;
		  last; # don't increment \/ \/
	    }elsif($opencount < 0){
		  return $self->_syntax_err("Mismatched ')'",$element->[1],$element->[2]);
	    }
	    $idx++;
      }

      if(!$closeidx){
	    return $self->_syntax_err("Unclosed '('",$firstoffset,$finaloffset);
      }
      return $closeidx;
}


sub _syntax_err{
      my $self = shift;
      my $message = shift;
      my $startoffset = shift;
      my $endoffset = shift;

      die {message => $message, startoffset => $startoffset,endoffset => $endoffset};

      return 0;
}

1;
