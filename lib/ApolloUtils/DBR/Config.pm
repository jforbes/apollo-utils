package ApolloUtils::DBR::Config;

use strict;
use base 'ApolloUtils::DBR';

#here is a list of the currently supported databases and their connect string formats
my %connectstrings = (
		      Mysql => 'dbi:mysql:database=-database-;host=-hostname-',
		      Pg    => 'dbi:Pg:dbname=-database-;host=-hostname-',
		     );


sub new {
  my( $package ) = shift;
  my %params = @_;
  my $self = {logger => $params{-logger}};

  bless( $self, $package );

  # so we can easily override these in the future if necessary
  $self->{dbr_tables} = {
			 fields    => 'dbr_fields',
			 instances => 'dbr_instances',
			 schemas   => 'dbr_schemas',
			 tables    => 'dbr_tables',
			};
  $self->{CONFIG} = {};

  return( $self );
}


sub load_file{
      my $self = shift;
      my %params = @_;

      my $dbr   = $params{'-dbr'}   or return $self->_error( '-dbr parameter is required'  );
      my $file  = $params{'-file'}  or return $self->_error( '-file parameter is required' );

      my @conf;
      my $setcount = 0;
      open (my $fh, '<', $file) || return $self->_error("Failed to open '$file'");

      while (my $row = <$fh>) {
	    if ($row =~ /^(.*?)\#/){ # strip everything after the first comment
		  $row = $1;
	    }

	    $row =~ s/(^\s*|\s*$)//g;# strip leading and trailing spaces
	    next unless length($row);

	    $conf[$setcount] ||= {};
	    if($row =~ /^---/){ # section divider. increment the count and skip this iteration
		  $setcount++;
		  next;
	    }

	    foreach my $part (split(/\s*\;\s*/,$row)){ # Semicolons are ok in lieu of newline cus I'm arbitrary like that.
		  my ($key,$val) = $part =~ /^(.*?)\s*=\s*(.*)$/;

		  $conf[$setcount]->{lc($key)} = $val;
	    }
      }
      close $fh;

      # Filter blank sections
      @conf = grep { scalar ( %{$_} ) } @conf;

      my $count;
      foreach my $instance (@conf){
	    $count++;

	    #don't bail out here on error, just skip the section
	    my $conf = $self->load_instance( %{$instance} ) || $self->_error("failed to load DBR conf file '$file' (stanza #$count)") && next;

	    if($conf->{dbr_bootstrap}){
		  #don't bail out here on error
		  $self->load_dbconf(
				     -dbr    => $dbr,
				     -handle => $conf->{handle},
				     -class  => $conf->{class}
				    ) || $self->_error("failed to load DBR config tables") && next;
	    }
      }

      return 1;

}

sub load_dbconf{
      my $self  = shift;
      my %params = @_;

      my $dbr    = $params{'-dbr'}    or return $self->_error( '-dbr parameter is required'    );
      my $handle = $params{'-handle'} or return $self->_error( '-handle parameter is required' );
      my $class  = $params{'-class'}  or return $self->_error( '-class parameter is required'  );


      my $dbh = $dbr->connect($handle,$class) || return $self->_error("Failed to connect to '$handle','$class'");

      return $self->_error('Failed to select instances') unless
	my $instances = $dbh->select(
				     -table => $self->{dbr_tables}->{instances},
				     -fields => 'instance_id schema_id class dbname username password host module'
				    );
      return $self->_error('Failed to select instances') unless
	my $schema_map = $dbh->select(
				      -table => $self->{dbr_tables}->{schemas},
				      -fields => 'schema_id handle display_name definition_mode enum_scheme enum_call',
				      -keycol => 'schema_id'
				     );

      foreach my $instance (@{$instances}){
	    my $schema = $schema_map->{ $instance->{schema_id} } || $self->_error("Schema not found for instance_id '$instance->{instance_id}'") && next;

	    $instance->{handle} = $schema->{handle}; # Yeah... kinda weak

	    #don't bail out here on error
	    my $conf = $self->load_instance( %{$instance} ) || $self->_error("failed to load DBR instance_id '$instance->{instance_id}'") && next;
      }

      return 1;
}

sub load_instance{
      my $self = shift;
      my %params = @_;


      my $conf = {
		  handle      => $params{handle}   || $params{name},
		  module      => $params{module}   || $params{type},
		  database    => $params{dbname}   || $params{database},
		  hostname    => $params{hostname} || $params{host},
		  user        => $params{username} || $params{user},
		  password    => $params{password},
		  class       => $params{class}       || 'master', # default to master
		  instance_id => $params{instance_id} || '',
		  schema_id   => $params{schema_id}   || '',
		  allowquery  => $params{allowquery}  || 0, 
		 };

      return $self->_error( 'handle/name parameter is required'     ) unless $conf->{handle};
      return $self->_error( 'module/type parameter is required'     ) unless $conf->{module};
      return $self->_error( 'database/dbname parameter is required' ) unless $conf->{database};
      return $self->_error( 'host[name] parameter is required'      ) unless $conf->{hostname};
      return $self->_error( 'user[name] parameter is required'      ) unless $conf->{user};
      return $self->_error( 'password parameter is required'        ) unless $conf->{password};

      $conf->{connectstring} = $connectstrings{$conf->{module}} || return $self->_error("module '$conf->{module}' is not a supported database type");


      foreach my $key (keys %{$conf}) {
	    $conf->{connectstring} =~ s/-$key-/$conf->{$key}/;
      }


      $conf->{dbr_bootstrap} = 1 if $params{dbr_bootstrap};

      $self->{CONFIG}->{ $conf->{handle} }->{ $conf->{class} } = $conf;

      if ($params{alias}) {
	    $self->{CONFIG}->{ $params{alias} }->{'*'} = $conf;
      }

      return $conf;

}

sub get_instance{
      my $self = shift;
      my $name = shift;
      my $class = shift;

      my $conf = $self->{CONFIG}->{$name}->{$class} || $self->{CONFIG}->{$name}->{'*'}; # handle aliases if there's no exact match

      return $conf || $self->_error("No DB instance found for '$name','$class'");

}
