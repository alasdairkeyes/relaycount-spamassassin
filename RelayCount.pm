# Copyright 2016 Alasdair Keyes
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

=head1 NAME

Mail::SpamAssassin::Plugin::RelayCount - RelayCount plugin

=head1 SYNOPSIS

  loadplugin     Mail::SpamAssassin::Plugin::RelayCount

=head1 REVISION

  Revision: 0.01 

=head1 DESCRIPTION

  Mail::SpamAssassin::Plugin::RelayCount is a plugin to score messages
  based on number of systems the email has been relayed through

  To find out more see
  https://github.com/alasdairkeyes/relaycount-spamassassin

=head1 AUTHOR

  Alasdair Keyes <alasdair@akeyes.co.uk>

  https://akeyes.co.uk/

=head1 LICENSE

  http://www.apache.org/licenses/LICENSE-2.0

=cut

package Mail::SpamAssassin::Plugin::RelayCount;

use strict;
use warnings;

use Mail::SpamAssassin;
use Mail::SpamAssassin::Constants qw(:ip);
our @ISA = qw(Mail::SpamAssassin::Plugin);

my $config_key = "relay_count";

## Constructor 

    sub new {
        my ($class, $mailsa) = @_;
        $class = ref($class) || $class;
        my $self = $class->SUPER::new( $mailsa );
        bless ($self, $class);

        # Register functions with Spamassassin
        $self->register_eval_rule ( 'minimum_relay_count_check' );
        $self->register_eval_rule ( 'maximum_relay_count_check' );

        return $self;
    }


    sub _get_all_public_ips {
        my $pms = shift || {};

        # Get all the IPs
        my @fullips = map { $_->{ip} } @{$pms->{relays_untrusted}};

        my @fullexternal = map {
            (!$_->{internal}) ? ($_->{ip}) : ()
            } @{$pms->{relays_trusted}};
        push (@fullexternal, @fullips);   # add untrusted set too

        # Strip out private IPs
        my $IP_PRIVATE = IP_PRIVATE;
        @fullexternal = grep {
            $_ !~ /$IP_PRIVATE/
        } @fullexternal;

        dbg("Pulled following IPs from PMS relays " . join(', ', @fullexternal));

        return @fullexternal;
    }


    # Override standard debug method by prepending it with $config_key for easier
    # checking in the logs
    sub dbg {
        my @message = @_;
        Mail::SpamAssassin::Plugin::dbg($config_key .': ' . (join(' ',@_) || '-'));
    }


    sub parse_config {
        my ($self, $opts) = @_;

        foreach my $option_key (qw/ blacklist_less_than_or_equal blacklist_greater_than_or_equal /) {
            if ($opts->{key} eq $option_key) {

                dbg("Loading " . ($opts->{ user_config } ? "user" : "global" ) . "_config for $option_key");

                my $value = $opts->{ value };

                if ($value !~ /^\d+$/) {
                    dbg("$option_key value $value invalid - setting to 0 - will not be checked");
                    $value = 0;
                }

                # Store
                $self->{ main }{ conf }{ $config_key }{ $option_key } = $value;

                # Inform SA, we handle this option
                $self->inhibit_further_callbacks();
                return 1;
            }
        }

        return 0;
    }


    sub minimum_relay_count_check {
        my ($self, $pms) = @_;

        my $blacklist_less_than_or_equal =
                $self->{ main }{ conf }{ $config_key }{ blacklist_less_than_or_equal };

        if ($blacklist_less_than_or_equal == 0) {
                dbg("blacklist_less_than_or_equal config option is set 0 - check not run");
                return 0;
        }

        my @public_ips = _get_all_public_ips($pms);
        dbg("Message touched " . scalar(@public_ips) . " public ips");

        return 1
            if (scalar(@public_ips) <= $blacklist_less_than_or_equal);

        return 0;
    }


    sub maximum_relay_count_check {
        my ($self, $pms) = @_;

        my $blacklist_greater_than_or_equal =
                $self->{ main }{ conf }{ $config_key }{ blacklist_greater_than_or_equal };

        if ($blacklist_greater_than_or_equal == 0) {
                dbg("blacklist_greater_than_or_equal config option is set 0 - check not run");
                return 0;
        }

        my @public_ips = _get_all_public_ips($pms);
        dbg("Message touched " . scalar(@public_ips) . " public ips");

        return 1
            if (scalar(@public_ips) >= $blacklist_greater_than_or_equal);

        return 0;
    }


1;

=head1 METHODS

=over

=item B<new( $class, $sa )>

  Plugin constructor

  Registers the rules with SpamAssassin

=item B<parse_config( $self, $opts )>

  SpamAssassin default config parsing method.

  Loads the blacklist/whitelist data from the global/user
  configuration files

=item B<minimum_relay_count_check( $self, $pms )>

  Registered method

  Called by SpamAssassin to check minimum relay count

=item B<maximum_relay_count_check( $self, $pms )>

  Registered method

  Called by SpamAssassin to check maximum relay count

=item B<dbg(@message)>

  Redefine SpamAssassin's dbg function, prepends with country_filter text,
  Makes debugging easier

=item B<_get_all_public_ips( $pms )>

  Takes the Spamassassin Per-message-status object and pulls
  out all non-private Relay IPs that this message has touched
  Returns an array of IP addresses

=back


=cut

