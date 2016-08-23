#
# Settings for the ORCiD interface
#


$c->{default_orcid_user_type} = "user";
$c->{default_orcid_allow_login} = "TRUE";

# new user fields for ORCiD

push @{$c->{fields}->{user}},
{ name => 'allow_orcid_login', type => 'boolean', input_style => 'radio', },
;




$c->{plugins}->{"Screen::NewOrcidUser"}->{params}->{disable} = 0;
       


