package Net::Google::Login::Status;
use strict;
use Moo 2;

use Filter::signatures;
use feature 'signatures';
no warnings 'experimental::signatures';

has wrong_password => ( is => 'ro' );
has logged_in      => ( is => 'ro' );

1;