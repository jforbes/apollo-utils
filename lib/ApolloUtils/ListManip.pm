# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# This software is Copyright (c) 2008 Daniel Norman
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License as
# published by the Free Software Foundation.
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# $Id: ListManip.pm,v 1.4 2008/09/16 05:58:52 impious Exp $
# $Source: /cvsroot/apollo-handler/apollo-utils/lib/ApolloUtils/ListManip.pm,v $
#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

package ApolloUtils::ListManip;

use base 'ApolloUtils';
use strict;
use POSIX;


sub slice{
      my $self = shift;
      my %params = @_;

      return $self->_error('list parameter must be specified') unless $params{list} && ref($params{list}) eq 'ARRAY';
      my $list = $params{list};


      # Split on

      # groupby
      # max per slice
      # rollover || evenout

      my @chunks;
      if($params{groupby}){
	    my $groupref = {};
	    my $groupby = $self->_mkarrayref($params{groupby}) || return $self->_error('groupby is invalid');

	    my $code = "sub {\n";
	    $code .= "\t my \$list = shift;\n";
	    $code .= "\t my \$gproot = {};\n";
	    $code .= "\t for my \$in (\@{\$list}){\n";
	    $code .= "\t\t my \$out = \$gproot->{" . join ('}->{', map {"\$in->{$_}"} @{$groupby}) . '} ||=[];' . "\n";
	    $code .= "\t\t push \@{\$out}, \$in;\n";
	    $code .= "\t }\n";
	    $code .= "\t return \$gproot\n";
	    $code .= "}";

	    $self->{logger}->logDebug2("Slice code: \n$code",'ApolloUtils::ListManip');

	    my $groupsub = eval $code;
	    return $self->_error("failed to compile groupcode $@") if $@;

	    my $grouproot = $groupsub->($list) || return $self->_error('groupsub failed');

	    my $addsub;
	    if($params{clean}){
		  $addsub = sub { { values => shift, list   => shift} };
	    }else{
		  $addsub = sub {
			my $values = shift;
			return {list => shift, %{$values}};
		  }
	    }

	    return $self->_error('_collapse_tree encountered an error') unless
	      $self->_collapse_tree($addsub,\@chunks, $grouproot,$groupby); # this could stand to be cleaned up a bit

      }else{
	    push @chunks, { list => $list };
      }

      if($params{max_count}){
	    for(my $chunkidx = 0; $chunkidx < scalar(@chunks); $chunkidx++){;
		  my $chunk = $chunks[$chunkidx];

		  my $listsize = scalar(@{$chunk->{list}});

		  #print STDERR "CIDX $chunkidx LSIZE: $listsize\n";
		  if ($listsize > $params{max_count}){
			my $partcount = ceil($listsize / $params{max_count});

			my $partsize   = $listsize / $partcount;
			my $firstpart  = floor($partsize);
			my $secondpart = ceil($partsize);
			#print STDERR "FP: $firstpart, SP $secondpart\n";

			my $moveparts = $partcount - 1; # leaving one part behind

			my $ct = 0;
			while($ct++ < $moveparts){

			      #print STDERR "LISTSIZE: $listsize, S: $firstpart L $secondpart\n";
			      my $newlist = [ splice( @{$chunk->{list}},$firstpart, $secondpart) ];

			      my $newchunk = { list => $newlist };
			      map { $newchunk->{$_} = $chunk->{$_} } grep {$_ ne 'list'} keys %{$chunk};
			      $newchunk->{chunkno} = $ct;

			      splice (@chunks, ++$chunkidx, 0, $newchunk);
			}

		  }
	    }
      }

      return \@chunks;
}


sub _collapse_tree{
      my $self    = shift;

      my $addsub  = shift;
      my $results = shift;
      my $branch  = shift;
      my $fields  = shift;

      my $values  = shift || [];
      my $levelct = shift || 0;

      return $self->_error('sanity error: branch must be hashref') unless ref($branch) eq 'HASH';

      my $kidct = (scalar(@{$fields}) - $levelct) - 1;
      return $self->_error('sanity error: may not have less than zero kids') if $kidct < 0;

      my $last = 1 if $kidct == 1;
      foreach my $value ( keys %{$branch} ) {
	    my $node = $branch->{$value};

	    my @myvalues = (@{$values},$value);

	    if ($kidct) {
		  return $self->_error('Recursion failed') unless
		    $self->_collapse_tree($addsub, $results, $node, $fields, \@myvalues, $levelct + 1)
	    } else {
		  return $self->_error('sanity error: node should be arrayref when no kids present') unless ref($node) eq 'ARRAY';

		  my $values = {};
		  map {$values->{$_} = shift @myvalues} @{$fields};
		  push @{$results}, $addsub->($values,$node);
	    }
      }

      return 1;
}

1;
