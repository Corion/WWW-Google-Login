package Net::Google::Login;

use strict;
use Moo 2;
use WWW::Mechanize::Chrome;
use Log::Log4perl ':easy';

use Filter::signatures;
use feature 'signatures';
no warnings 'experimental::signatures';

use Net::Google::Login::Status;

=head1 NAME

Net::Google::Login - log a mechanize object into Google

=head1 SYNOPSIS

    my $mech = WWW::Mechanize::Chrome->new(
        headless => 1,
        data_directory => tempdir(CLEANUP => 1),
        user_agent => 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/64.0.3282.39 Safari/537.36+',
    );
    $mech->viewport_size({ width => 480, height => 640 });
    
    $mech->get('https://keep.google.com');
    
    my $login = Net::Google::Login->new(
        mech => $mech,
    );
    
    if( $login->is_login_page()) {
        my $res = $login->login(
            user => 'a.u.thor@gmail.com',
            password => 'my-secret-password',
            headless => 1
        );
    
        if( $res->wrong_password ) {
            # ?
        } elsif( $res->logged_in ) {
            # yay
        } else {
            # some other error
        }
    };

=head1 DESCRIPTION

This module automates logging in a (Javascript capable) WWW::Mechanize
object into Google. This is useful for scraping information from Google
applications.

Currently, this module only works in conjunction with L<WWW::Mechanize::Chrome>,
but ideally it will evolve to not requiring Javascript or Chrome at all.

=cut

has 'logger' => (
    is => 'ro',
    default => sub {
        get_logger(__PACKAGE__),
    },
);

has 'mech' => (
    is => 'ro',
    is_weak => 1,
);

has 'console' => (
    is => 'rw',
);

sub mask_headless( $self, $mech ) {
    my $console = $mech->add_listener('Runtime.consoleAPICalled', sub {
      warn "[] " . join ", ",
          map { $_->{value} // $_->{description} }
          @{ $_[0]->{params}->{args} };
    });
    $self->console($console);
    
    $mech->block_urls(
        'https://fonts.gstatic.com/*',
    );
    
    my $id = $mech->driver->send_message('Page.addScriptToEvaluateOnNewDocument', source => <<'JS' )->get;
Object.defineProperty(navigator, 'webdriver', {
    get: () => false
});

Object.defineProperty(navigator, 'plugins', {
    get: () => [1,2,3,4,5]
});
Object.defineProperty(navigator, 'languages', {
    get: () => ['en-US', 'en'],
});

const myChrome = {
    "app":{"isInstalled":false},
    "webstore":{"onInstallStageChanged":{},"onDownloadProgress":{}},
    "runtime": {}
};
Object.defineProperty(navigator, 'chrome', {
    get: () => { console.log("chrome property accessed"); myChrome }
});

const connection = { rtt: 100, downlink: 1.6, effectiveType: "4g", downlinkMax: null };
Object.defineProperty(navigator, 'connection', {
    get: () => (connection),
});

const originalQuery = window.navigator.permissions.query;
window.navigator.permissions.query = (parameters) => {
    console.log("permission query for " + parameters.name);
    parameters.name === 'notifications' ?
      Promise.resolve({ state: Notification.permission }) :
      originalQuery(parameters)
};

console.log("Page " + window.location);
JS

    #$mech->agent('Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/64.0.3282.39 Safari/537.36+');
    $mech->get('about:blank');
}

sub login_headfull( $self, %options ) {
    my $l = $options{ logger } || $self->logger;
    my $mech = $options{ mech } || $self->mech;
    my $user = $options{ user };
    my $password = $options{ password };
    my $logger = $self->logger;
    
    my @email = $mech->wait_until_visible( selector => '//input[@type="email"]' );
    
    my $username = $email[0]; # $mech->xpath('//input[@type="email"]', single => 1 );
    $username->set_attribute('value', $user);
    $mech->click({ xpath => '//*[@id="identifierNext"]' });
    
    # Give time for password page to load
    $mech->wait_until_visible( selector => '//input[@type="password"]' );
    my $field = $mech->selector( '//input[@type="password"]', one => 1 );
    #print $field->get_attribute('id'), "\n";
    #print $field->get_attribute('name'), "\n";
    #print $field->get_attribute('outerHTML'), "\n";
    my $password_field =
      $mech->xpath( '//input[@type="password"]', single => 1 );

    my $password_html = $mech->selector('#password', single => 1 );
    $mech->click( $password_html ); # html "field" to enable the real field
    #$mech->sleep(10);
    $mech->sendkeys( string => $password );
    $logger->info("Password entered into field");

    # Might want to uncheck 'save password' box for future
    $logger->info("Clicking Sign in button");

    $mech->click({ selector => '#passwordNext', single => 1 }); # for headful
}

sub login_headless( $self, %options ) {
    my $l = $options{ logger } || $self->logger;
    my $mech = $options{ mech } || $self->mech;
    my $user = $options{ user };
    my $password = $options{ password };
    my $logger = $self->logger;

    # Click in Login Email form field
    warn "Waiting for email entry field";
    $mech->wait_until_visible( selector => '//input[@type="email"]' );
    my $email = $mech->selector( '//input[@type="email"]', single => 1 );
    print $email->get_attribute('id');
    print $email->get_attribute('name');
    print $email->get_attribute('outerHTML');
    $logger->info("Clicking and setting value on Email form field");
    
    $mech->field( Email => $user );
    $mech->sleep(1);
    $logger->info("Clicking Next button");
    my $signIn_button = $mech->xpath( '//*[@name = "signIn"]', single => 1 );
    my $signIn_class = $signIn_button->get_attribute('class');
    #warn "Button class name is '$signIn_class'";
    $mech->click_button( name => 'signIn' );

    # Give time for password page to load
    #warn "Waiting for password field";
    $mech->wait_until_visible( selector => '//input[@type="password"]' );
    $logger->info("Clicking on Password form field");

    my $password_field =
        $mech->xpath( '//input[@type="password"]', single => 1 );

    $mech->click($password_field);    # when headless
    #$mech->sleep(10);
    $logger->info("Entering password one character at a time");
    $mech->sendkeys( string => $password );
    $logger->info("Password entered into field");

    # Might want to uncheck 'save password' box for future
    $logger->info("Clicking Sign in button");
    $mech->dump_forms;
    #for ($mech->xpath('//form//*[@id]')) {
    #    warn $_->get_attribute('id');
    #};

    # We should propably wait until a lot of the scripts have loaded...

    $mech->click({ xpath => '//*[@id = "signIn"]', single => 1 });    # for headless
    $mech->sleep(15);
    $mech->wait_until_invisible(xpath => '//*[contains(text(),"Loading...")]');
}

=head2 C<< ->is_login_page >>

    if( $login->is_login_page ) {
        $login->login( user => $user, password => $password );
    };

=cut

sub is_login_page( $self ) {
       $self->is_login_page_headless
    || $self->is_login_page_headfull
}

=head2 C<< ->is_login_page_headless >>

=cut

sub is_login_page_headless( $self ) {
    () = $self->mech->xpath( '//*[@name = "signIn"]', maybe => 1 )
}

=head2 C<< ->is_login_page_headfull >>

=cut

sub is_login_page_headfull( $self ) {
    () = $self->mech->xpath( '//*[@id="identifierNext"]', maybe => 1 )
}

=head2 C<< ->login >>

    my $res = $login->login(
        user => 'example@gmail.com',
        password => 'supersecret',
    );
    if( $res->logged_in ) {
        # yay
    }

=cut

sub login( $self, %options ) {
    my $res;
    if( $self->is_login_page_headless ) {
        $res = $self->login_headless( %options )
    } elsif( $self->is_login_page_headfull ) {
        $res = $self->login_headfull( %options )
    } else {
        $res = $self->login_headfull( %options )
    }
    $res
}

sub click_text( $self, $text ) {
    my $mech = $self->mech;
    my $query = qq{//*[text() = "$text"]};
    my @nodes = $mech->wait_until_visible(xpath => $query, any => 1 );
    sleep(15);
    $mech->click( $nodes[0] );
    # Just so I can see that we clicke don that button
    warn "Clicked on '$text'";
    $mech->sleep(15);
}

sub click_and_type( $self, $text, $input ) {
    my $mech = $self->mech;
    $self->click_text( $text );
    $mech->sendkeys( string => $input );
}

1;