# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# The contents of this file are Copyright (c) 2006/2007 Daniel Norman.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License as
# published by the Free Software Foundation.
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

package ApolloUtils::Console;


use ApolloUtils;
use strict;
no warnings 'redefine';

our @ISA = qw(ApolloUtils);

use Curses;

my %BUTTONS = (
	       'up'    => KEY_UP,
	       'down'  => KEY_DOWN,
	       'left'  => KEY_LEFT,
	       'right' => KEY_RIGHT,
	       'backspace' => KEY_BACKSPACE
	      );

my $MAX_COMMAND_LINE_POS = 29;
my $MAX_HANDHELD_LINE_POS = 19;


sub new {
      my $pkg = shift;
      my %params = @_;
      my $self = {};
      bless ($self , $pkg);
      $self->{pkg} = $pkg;

      $self->{params} = \%params;

      my $initct = 1;
      if ($params{doubleinit}){
	 $initct++;
      }

      while($initct){
         Curses::initscr();
         Curses::clear();
         Curses::noecho();
         Curses::cbreak();
	 $initct--;
	 select (undef,undef,undef,0.5) if $initct;
      }

      my ($hmax,$wmax);
      Curses::getmaxyx($hmax, $wmax);
      $self->{hmax} = $hmax;
      $self->{wmax} = $wmax;
      $self->{winheight} = $params{height} || $hmax;
      $self->{winwidth} =  $params{width}  || $wmax;

      $self->{winheight} = $self->{hmax} if $self->{hmax} < $self->{winheight};
      $self->{winwidth} = $self->{wmax} if $self->{wmax} < $self->{winwidth};

      my $startx = ($wmax - $self->{winwidth}) / 2;
      my $starty = ($hmax - $self->{winheight}) / 2;

      $self->{window} = Curses::newwin($self->{winheight}, $self->{winwidth}, $starty, $startx);
      
      Curses::keypad($self->{window}, 1);

      return $self;
};


sub menu{
      my $self = shift;
      my %params = @_;

      $params{wrap} ||= $self->{params}->{wrap};
      my $startx = $params{'x'} || 0;
      my $starty = $params{'y'};
      $starty = $self->{nexty} unless defined($starty);
      $starty ||= 0;

      my @menu;
      my @keys;

      my $highlight;
      my $choicect;
      if(ref($params{choices}) eq 'ARRAY'){
	    if($params{paired}){
		  my @hopper = @{$params{choices}};
		  while(@hopper){
			$choicect++;
			my $key = shift @hopper;

			if($params{selected} eq $key){
			      $highlight ||= $choicect
			}

			push @keys, $key;
			push @menu, shift @hopper;
		  }
	    }else{
		  @menu = @{$params{choices}};

		  if($params{selected} =~ /^\d+$/){
			$highlight = $params{selected};
		  }

		  $choicect = scalar(@menu);
	    }
      }elsif(ref($params{choices}) eq 'HASH'){
	    @keys = sort {$params{choices}->{$a} cmp $params{choices}->{$b}} keys %{$params{choices}};
	    foreach my $key (@keys){
		  if($params{selected} eq $key){
			$highlight ||= $choicect
		  }
		  push @menu, $params{choices}->{$key};
		  $choicect++;
	    }
      }else{
	    return $self->_error('invalid value for choices');
      }

      ########################### multi-field alignment logic #####################
      # #### HERE HERE HERE split this into its own routine
      # first get the maxes
       my %fieldmax;
       foreach my $row (@menu){
 	    if(ref($row) eq 'ARRAY'){
 		  my $i = 0;
 		  foreach my $field (@{$row}){
 			$i++;
 			my $len = length($field);
 			$fieldmax{$i} = $len if $len > $fieldmax{$i};
 		  }
 	    }
       }

       my $nocrop = $params{nocrop};
       if($nocrop){
 	    $nocrop = [$nocrop] unless ref($nocrop);
 	    return $self->_error('invalid value for parameter nocrop') unless ref($nocrop) eq 'ARRAY';
       }else{
 	    $nocrop = [];
       }

       my $fieldalign = $params{fieldalign} || {};

       my %fieldwidth;
       my $currlen = $self->{winwidth};

       foreach my $index (@{$nocrop},sort keys %fieldmax){
 	    next unless $fieldmax{$index} && $currlen > 0;
 	    my $len = $fieldmax{$index};
 	    $len = $currlen if $len > $currlen;
 	    $currlen -= $len;

 	    $fieldwidth{$index} = $len;
 	    delete $fieldmax{$index};
 	    $currlen--; # deduct 1 for a space
      }

      my @display;
      foreach my $item (@menu){
	    my $line;
	    if(ref($item) eq 'ARRAY'){
		  my @fields;
		  my $i = 0;
		  foreach my $field (@{$item}){
			$i++;
			if($fieldwidth{$i}){
			      my $len = length($field);
			      if($len > $fieldwidth{$i}){
				    $field = substr($field,0,$fieldwidth{$i});
			      }else{
				    my $pad = ' ' x ($fieldwidth{$i} - $len);
				    if($fieldalign->{$i} =~ /^R/i){ # right align
					  $field = $pad . $field;
				    }else{ # left align
					  $field .= $pad;
				    }
			      }
			      push @fields, $field;
			}
		  }
		  $line = join(' ',@fields);
	    }else{
		  $line = $item;
		  $line = substr($line,0,$self->{winwidth}) if length($line) > $self->{winwidth};
	    }
	    push @display, $line;
      }

      #############################################################################

      $highlight ||= 1;
      my $choice = 0;
      my $selected = 0;
      my $go;

      #Curses::clear($self->{window});

      if ($params{prompt}) {
	    Curses::addstr($self->{window},$starty, $startx, $params{prompt});
	    $starty += 2;
      }

      my $slotct = $self->{winheight} - $starty;
      $slotct = $choicect if $choicect < $slotct;

      my $yshift = 0;
      while (1) {
	    my $x = $startx;
	    my $y = $starty;

	    # debug
	    #Curses::addstr($self->{window}, 0, 0, "H$highlight SC $slotct YS $yshift");
	    #Curses::clrtoeol($self->{window});

	    #shit this yshift logic is confusing
	    if ($highlight > ($slotct + $yshift)){
		  $yshift = ($highlight - $slotct);
	    }elsif($highlight <= $yshift){
		  if($yshift - $highlight > $slotct){
			$yshift = ($highlight - $slotct);
		  }else{
			$yshift--;
		  }
		  $yshift = 0 unless $yshift >= 0;
	    }

	    #Curses::addstr($self->{window}, 1, 0, "H$highlight SC $slotct YS $yshift");
	    #Curses::clrtoeol($self->{window});

	    for (my $i = $yshift; $i < $choicect; $i++) {
		  my $line = $display[$i];

		  if ($highlight == $i + 1) {
			Curses::attron($self->{window}, A_REVERSE);
			Curses::addstr($self->{window}, $y, $x, $line);
			Curses::attroff($self->{window}, A_REVERSE);
		  } else {
			Curses::addstr($self->{window}, $y, $x, $line);
		  }
		  Curses::clrtoeol($self->{window});
		  $y++;
	    }

	    Curses::refresh($self->{window});

	    my $c = Curses::getch($self->{window});
	    return $self->_error('Failed to get input from console') if $c == -1;

	    if ($c == KEY_UP) {
		  if ($highlight == 1) {
			if($params{wrap}){
			      $highlight = $choicect;
			}
		  } else {
			$highlight--;
		  }
	    } elsif ($c == KEY_DOWN) {
		  if ($highlight == $choicect) {
			if($params{wrap}){
			      $highlight = 1;
			}
		  } else {
			$highlight++;
		  }
	    } elsif ($c eq "\n" || ($self->{rightselect} && ($c == KEY_RIGHT))) {
		  $go = 1;
	    } else {
		  #$self->_handlechar($c);
		  #print STDERR "BUTTON $c\n";
		  if($params{buttons}){
			foreach my $button (keys %{$params{buttons}}){
			      if($BUTTONS{$button}){
				    if($BUTTONS{$button} eq $c){
					  $choice = $params{buttons}->{$button};
				    }
			      }else{
				    if($button eq $c){
					  $choice = $params{buttons}->{$button};
				    }
			      }
			      last if $choice;
			}
		  }
	    }

	    if(@keys){
		  $selected = $keys[$highlight - 1];
	    }elsif(ref($params{choices}) eq 'ARRAY'){
		  $selected = $highlight;
	    }

	    $choice = $selected if $go;

	    last if ($choice);
      }

      $self->clear();

      #print STDERR "CHOICE $choice\n";
      if(wantarray()){
	    return ($choice,$selected);
      }else{
	    return $choice;
      }

}

sub _handlechar{
      my $self = shift;
      my $char = shift;

      #?

      return 1;
}

sub skip{
      my $self = shift;
      $self->{nexty}++;
      $self->{nexty} = 0 if $self->{nexty} > $self->{winheight};
      return 1;
}

sub clear{
      my $self = shift;
      Curses::clear($self->{window});

      $self->{nexty} = 0;
      return 1;
}

sub print{
      my $self = shift;

      my %params;
      if(scalar(@_) == 1){
	    $params{text} = $_[0];
      }else{
	    %params = @_;
      }

      $params{wrap} ||= $self->{params}->{wrap};

      my $x = $params{'x'} ||= 0;
      my $y = $params{'y'};
      $y = $self->{nexty} unless defined($y);

      my @lines = split("\n",$params{text});

      Curses::attron($self->{window},A_BOLD) if $params{bold};

      my $maxlength = $self->{winwidth} - $x;

      my @reallines;
      my $txtwidth = 0;
      foreach my $str (@lines){
	    unless($params{wrap}){
		  if (length($str) > $maxlength){
			$str = substr($str,0,$maxlength);
		  }
	    }

	    while(length($str)){
		my $line = substr($str,0,$maxlength);
		substr($str,0,$maxlength) = '';

                push @reallines, $line;
                my $len = length($line);
                $txtwidth = $len if $len > $txtwidth;
	    }
      }

      my $txtheight = scalar(@reallines);

      if ($params{center} || $params{vcenter}) {
         $y = int(($self->{winheight} - $y - $txtheight)/2) + $y;
      }
      if ($params{center} || $params{hcenter}) {
         $x = int(($self->{winwidth} - $x - $txtwidth)/2) + $x;
	    }

      foreach my $line (@reallines) {
	  Curses::addstr($self->{window},$y++,$x,$line);
	  Curses::clrtoeol($self->{window});
      }

      Curses::attroff($self->{window},A_BOLD) if $params{bold};
      Curses::refresh($self->{window});

      $self->{nexty} = $y; # already incremented from above /\
      $self->{nexty} = 0 if $self->{nexty} > $self->{winheight};

      return 1;
}

sub prompt{
      my $self = shift;
      my %params = @_;

      my $y = $params{'y'};
      if ($params{prompt}) {
	    $self->print(
			 'x' => $params{'x'},
			 'y' => $params{'y'},
			 text => $params{prompt},
			 wrap => 1,
			);
	    $y = $self->{nexty};
      }
      $y = $self->{nexty} unless defined($y);
      $params{'x'} ||= 0;

      if($params{nextline} || !$params{prompt}){
	    Curses::move($self->{window},$y++,$params{'x'});
	    $self->{nexty} = $y; # already incremented from above /\
	    $self->{nexty} = 0 if $self->{nexty} > $self->{winheight};
      }

      Curses::echo() unless $params{noecho};

      my %buttoncheck;

      if ($params{buttons}) {
	    foreach my $button (keys %{$params{buttons}}) {
		  my $retval = $params{buttons}->{$button};

		  if ($BUTTONS{$button}) {
			$buttoncheck{ $BUTTONS{$button} } = $retval;
		  } else {
			$buttoncheck{ $button } = $retval;
		  }
	    }
      }

      my $str;

      # The last x position to determine whether or not to move up a row
      my $x_last;
      
      while (1) {

	    my $c = Curses::getch($self->{window});
	    return $self->_error('Failed to get input from console') if $c == -1;
	    
	    # Current x, y coordinates of screen cursor
	    my $x;
	    my $y;
	    
	    Curses::getyx($self->{window}, $y, $x);
	    
	    # Save these off in case 'getyx' changes them periodically
	    my $x_static = $x;
	    my $y_static = $y;
	    
	    if(!defined $x_last){
		  $x_last = $x_static;
	    }

	    if($c eq "\n" || ($self->{rightselect} && ($c == KEY_RIGHT))){
		  last
	    }elsif( defined($buttoncheck{$c}) ) { # bail out if we get a good buttonpress
		  return $buttoncheck{$c};	    
	    }elsif( $c eq KEY_BACKSPACE ){
		  
		  # If we received a 'backspace', we assume the user is using the command line console
		  # and so we assume the dimensions of the screen are as such	  
		  
		  # At the beginning of the row, so move up one row
		  if($x_static == 0 and $x_last == 0){			
			Curses::move($self->{window}, $y_static - 1, $MAX_COMMAND_LINE_POS);
		  }
		  
		  Curses::delch($self->{window});
		  
		  $x_last = $x_static;
		  next;
		  
	    }elsif(ord($c) == 127){
		  # If we received a 'delete' we assume the user is using the hand held console and
		  # so we assume the dimensions of the screen are as such
		  
		  # Delete characters depending on how close we were to the edge of the screen
		  if($x_static == 2){
			if($y_static != 0){
			      Curses::deleteln($self->{window});
			      Curses::move($self->{window}, $y_static - 1, $MAX_HANDHELD_LINE_POS);	      
			}
			else{
			      Curses::move($self->{window}, $y_static, 0);			      
			}
		  }elsif($x_static == 1){			
			Curses::deleteln($self->{window});
			Curses::move($self->{window}, $y_static - 1, $MAX_HANDHELD_LINE_POS - 1);						
		  }elsif($x_static == 0){			
			Curses::deleteln($self->{window});
			Curses::move($self->{window}, $y_static - 1, $MAX_HANDHELD_LINE_POS - 2);						
		  }
		  else{
			Curses::move($self->{window}, $y_static, $x_static - 3);			
		  }
		  
		  Curses::clrtoeol($self->{window});
		  $x_last = $x_static;
		  next;
		  
	    }
	    elsif( length ($c) > 1 ){
		  $x_last = $x_static;
		  next; # cheap way to detect nonprintables
	    }
	    
	    $x_last = $x_static;

	    $str .= $c;

      }

      Curses::noecho() unless $params{noecho};

      return $str;
}


sub wait{
      my $self = shift;
      my $c = Curses::getch($self->{window});
      # check for keymaps here
      return $c;
}
sub beep{
      my $self = shift;
      Curses::beep();
      return 1;
}

sub errbeep{
      my $self = shift;

      Curses::beep();
      select(undef,undef,undef,.15);
      Curses::beep();

      return 1;
}

sub finish {
      my $self = shift;
      Curses::endwin();
}

sub DESTROY{
      my $self = shift;
      $self->finish();
}

sub width {
  my $self = shift;
  return $self->{winwidth};
}

sub height {
  my $self = shift;
  return $self->{winheight};
}

1;

