=head1 NAME

EPrints::Plugin::Screen::NewOrcidUser

=cut


package EPrints::Plugin::Screen::NewOrcidUser;

use EPrints::Plugin::Screen;

@ISA = ( 'EPrints::Plugin::Screen' );

use strict;

sub new
{
	my( $class, %params ) = @_;

	my $self = $class->SUPER::new(%params);

	$self->{actions} = [qw/ create cancel /];

	$self->{appears} = [
		{ 
			place => "admin_actions_system", 	
			position => 1001, 
		},
	];

	return $self;
}

sub can_be_viewed
{
	my ( $self ) = @_;

	return $self->allow( "create_user" );
}

sub allow_cancel
{
	my ( $self ) = @_;

	return 1;
}

sub action_cancel
{
	my( $self ) = @_;

	$self->{processor}->{screenid} = "Admin";
}

sub allow_create
{
	my ( $self ) = @_;

	return $self->allow( "create_user" );
}

sub action_create
{
	my( $self ) = @_;

	my $repo = $self->{session};
	my $xml = $repo->xml;
	my $ds = $repo->dataset( "user" );

	my $candidate_username = $repo->param( "username" );
	my $candidate_orcid = $repo->param( "userorcid" );

	unless( EPrints::Utils::is_set( $candidate_username ) )
	{
		$self->{processor}->add_message( 
			"warning",
			$self->html_phrase( "no_username" ) );
		return;
	}
	unless( EPrints::Utils::is_set( $candidate_orcid ) )
	{
		$self->{processor}->add_message( 
			"warning",
			$self->html_phrase( "no_userorcid" ) );
		return;
	}

	if ( defined EPrints::DataObj::User::user_with_username( $repo, $candidate_username ) )
	{
		$self->{processor}->add_message( 
			"error",
			$self->html_phrase( "user_exists",
				username=>$xml->create_text_node( $candidate_username ) ) );
		return;
	}

	if ( $candidate_orcid !~ /[0-9]{4}-[0-9]{4}-[0-9]{4}-[0-9xX]{4}/ )
	{
		$self->{processor}->add_message( 
			"error",
			$self->html_phrase( "wrong_format",
				orcid => $xml->create_text_node( $candidate_orcid ) ) );
		return;
	}

	my $user_list = $ds->search(
		filters => [ {meta_fields => [ 'orcid' ], value => $candidate_orcid, match => 'EQ'} ] );

	if ( $user_list->count )
	{
		my $duplicates = $user_list->ids;
		my $duplicate_list = join(",", @$duplicates);
		$self->{processor}->add_message( 
			"error",
			$self->html_phrase( "user_orcid_exists",
				orcid=>$xml->create_text_node( $candidate_orcid ),
				userids=>$xml->create_text_node( $duplicate_list )
 			) );
		return;
	}

	my $user_type = $repo->config( "default_orcid_user_type" ); 
	my $allow_login = $repo->config( "default_orcid_allow_login" ); 

	# get use data from ORCID
#        my $url = $repo->get_conf( "orcid_tier_2_api" );
        my $url = $repo->get_conf( "orcid_public_api" );
        my $url_v = $repo->get_conf( "orcid_version" );
        $url .= "v".$url_v."/".$candidate_orcid;
        $url .= "/orcid-bio";

print STDERR "req[".$url."]\n";
        my $req = HTTP::Request->new("GET",$url);
        $req->header( "accept" => "application/json" );

        my $ua = LWP::UserAgent->new;
        my $response = $ua->request($req);

        if (200 != $response->code)
        {
		$self->{processor}->add_message( 
			"error",
			$self->html_phrase( "lookup_error", 
				orcid => $xml->create_text_node( $candidate_orcid ), 
				code=>$xml->create_text_node( $response->code ) ) );
		return;	
        }
	my $content = $response->content;
	my $json_vars = JSON::decode_json($content);
print STDERR "got[".Data::Dumper::Dumper($json_vars)."]\n";
	my $returned_id = $json_vars->{'orcid-profile'}->{'orcid-identifier'}->{'path'};
	my $given = $json_vars->{'orcid-profile'}->{'orcid-bio'}->{'personal-details'}->{'given-names'}->{'value'};
	my $family = $json_vars->{'orcid-profile'}->{'orcid-bio'}->{'personal-details'}->{'family-name'}->{'value'};

print STDERR "\n\n\ng[$given] f[$family] o[$returned_id]\n";
	if ( $candidate_orcid ne $returned_id )
	{
		$self->{processor}->add_message( 
			"error",
			$self->html_phrase( "ids_do_not_match",
				orcid => $xml->create_text_node( $candidate_orcid ) ) );
		return;
	}

	# Attempt to create a new account
	$self->{processor}->{user} = $ds->create_object( $self->{session}, { 
		username => $candidate_username,
		orcid => $candidate_orcid,
		name => { given => $given, family => $family },
		allow_orcid_login => $allow_login,
		usertype => $user_type } );

	if( !defined $self->{processor}->{user} )
	{
		my $db_error = $repo->get_database->error;
		$repo->get_repository->log( "Database Error: $db_error" );
		$self->{processor}->add_message( 
			"error",
			$self->html_phrase( "db_error" ) );
		return;
	}

	$self->{processor}->{dataset} = $ds;
	$self->{processor}->{dataobj} = $self->{processor}->{user};
	$self->{processor}->{screenid} = "Workflow::Edit";
}

sub render
{
	my ( $self ) = @_;

	my $repo = $self->{session};
	my $xml = $repo->xml;

	my $frag = $xml->create_element( "div", class=>"ep_block" );

	$frag->appendChild( $self->html_phrase( "blurb" ) );

	my $form = $frag->appendChild( $repo->render_form( "GET" ) );
	$form->appendChild( $repo->render_hidden_field ( "screen", "NewOrcidUser" ) );		
	my $ds = $repo->dataset( "user" );
	my $username_field = $ds->get_field( "username" );
	my $usertype_field = $ds->get_field( "usertype" );
	my $userorcid_field = $ds->get_field( "orcid" );
	my $div = $form->appendChild( $xml->create_element( "div", style=>"margin-bottom: 1em" ) );
	$div->appendChild( $username_field->render_name( $repo ) );
	$div->appendChild( $xml->create_text_node( ": " ) );
	$div->appendChild( 
		$xml->create_element( 
			"input",
			"maxlength"=>"255",
			"name"=>"username",
			"id"=>"username",
			"class"=>"ep_form_text",
			"size"=>"20", ));

	$div->appendChild( $userorcid_field->render_name( $repo ) );
	$div->appendChild( $xml->create_text_node( ": " ) );
	$div->appendChild( 
		$xml->create_element( 
			"input",
			"maxlength"=>"255",
			"name"=>"userorcid",
			"id"=>"userorcid",
			"class"=>"ep_form_text",
			"size"=>"20", ));

	my %buttons = (
		cancel => $self->phrase( "action:cancel:title" ),
		create => $self->phrase( "action:create:title" ),
		_order => [ "create", "cancel" ]
	);

	$form->appendChild( $repo->render_action_buttons( %buttons ) );
	
	return( $frag );
}	

1;

