=head1 NAME

EPrints::Plugin::Screen::Login::OrcidLogin

=cut

package EPrints::Plugin::Screen::Login::OrcidLogin;

use EPrints::Plugin::Screen;

@ISA = qw( EPrints::Plugin::Screen );

use strict;

sub new
{
	my( $class, %params ) = @_;

	my $self = $class->SUPER::new(%params);
	
	$self->{appears} = [
		{
			place => "login_tabs",
			#place => "key_tools",
			position => 101,
		},
	];
        $self->{actions} = [qw/ login /];

	return $self;
}

sub allow_login
{
        return 1;
}

sub action_login
{
	my( $self ) = @_;
print STDERR "########################################  /OrcidLogin::action_login called \n";

	my $processor = $self->{processor};
	my $repo = $self->{repository};
	my $xml = $repo->xml;
	my $orcidid = $repo->param( "login_orcidid" );

	if ( $orcidid !~ /[0-9]{4}-[0-9]{4}-[0-9]{4}-[0-9xX]{4}/ )
	{
		$self->{processor}->add_message( 
			"error",
			$self->html_phrase( "wrong_format",
				orcid => $xml->create_text_node( $orcidid ) ) );
		return;
	}

	my $ds = $repo->dataset( "user" );
	my $user;
	my $user_list = $ds->search(
		filters => [ {meta_fields => [ 'orcid' ], value => $orcidid, match => 'EQ'} ] );

	if ( $user_list->count > 1 )
	{
		$self->{processor}->add_message( 
			"error",
			$self->html_phrase( "not_unique",
				orcid => $xml->create_text_node( $orcidid ) ) );
		return;
	}
	elsif ( 0 == $user_list->count )
	{
		$self->{processor}->add_message( 
			"error",
			$self->html_phrase( "not_found",
				orcid => $xml->create_text_node( $orcidid ) ) );
		return;
	}
	else
	{
		$user = $user_list->item(0);
	}
	my $allowed_to_login = $user->get_value( "allow_orcid_login" );
	unless ( $allowed_to_login && $allowed_to_login eq "TRUE" )
	{
		$self->{processor}->add_message( 
			"error",
			$self->html_phrase( "not_allowed",
				orcid => $xml->create_text_node( $orcidid ) ) );
		return;
	}
	

print STDERR "########################################  /OrcidLogin::action_login about to authenticate user[".$user->get_id."] \n";
	my $auth_url = $repo->call( "get_orcid_authorise_url", $repo, $user->get_id(), 0, "user_login", $orcidid ); 

print STDERR "########################################  /OrcidLogin::action_login about to authenticate url[".$auth_url."] \n";

        $self->{repository}->redirect( $auth_url );

}

sub render
{
	my( $self, %bits ) = @_;

	my $repo = $self->{repository};
	my $xml = $repo->xml;

	$bits{problems} = $repo->make_doc_fragment;
	$bits{input_orcidid} = $repo->render_input_field(
			class => "ep_form_text",
			id => "login_orcidid",
			name => 'login_orcidid' );

	my $title = $self->render_title;
	$bits{login_button} = $repo->render_button(
			name => "_action_login",
			value => $repo->xhtml->to_text_dump( $title ),
			class => 'ep_form_action_button', );
	$repo->xml->dispose( $title );

	my $form = $repo->render_form( "POST" );
	$form->appendChild( $self->render_hidden_bits );
	$form->appendChild( $self->html_phrase( "page_layout", %bits ) );

	my $script = $repo->make_javascript( '$("login_orcidid").focus()' );
	$form->appendChild( $script );

	return $form;
}



1;


