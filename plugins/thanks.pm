use POE;
my %karma = ();

my $moar_karma = sub {
	my $n = shift;
	$karma{$n} //= 0;
	$karma{$n}++;
};

{
	schemata => {
		0 => [
			"CREATE TABLE thanks (from_nick TEXT NOT NULL, to_nick TEXT NOT NULL,
				created_at INT NOT NULL DEFAULT CURRENT_TIMESTAMP)",
			"CREATE INDEX thanks_to_idx ON thanks (to_nick)",
			"CREATE INDEX thanks_from_idx ON thanks (from_nick)",
			"CREATE INDEX thanks_time_idx ON thanks (created_at)",
		],
	},
	on_load => sub {
		my $res = $BotDb::db->selectall_arrayref("SELECT * FROM thanks", {Slice => {}});
		$moar_karma->($_->{to_nick}) for @$res;
	},
	irc_commands => {
		karma => sub {
			my ($source, $targets, $args, $auth) = @_;
			BotIrc::check_ctx() or return;

			my @args = split(/\s+/, $args);
			my @karma = ();
			for my $n (@args) {
				next if (!exists $karma{lc $n});
				my $k = int($karma{lc $n}/10);
				next if !$k;
				push @karma, "$n: $k";
			}
			if (!@karma) {
				BotIrc::send_wisdom("the karma of the given users is shrouded in the mists of uncertainty.");
				return;
			}
			BotIrc::send_wisdom("the Genuine Real Life Karma™ REST API results are back! ". join(',  ', @karma));
		},
		topkarma => sub {
			my ($source, $targets, $args, $auth) = @_;
			BotIrc::check_ctx() or return;

			my $res = $BotDb::db->selectall_arrayref("SELECT to_nick, count(to_nick) AS nicksum FROM thanks GROUP BY to_nick ORDER BY nicksum DESC LIMIT 5");
			if (!ref($res) || @$res < 5) {
				BotIrc::send_noise("not enough data for a top karma list");
				return;
			}
			splice @$res, 5;
			my @top = map { $_->{to_nick} .": ". int($_->{nicksum}/10) } @$res;

			BotIrc::send_wisdom("top karmic beings: ". join(',  ', @top));
		}
	},
	irc_on_public => sub {
		BotIrc::check_ctx() or return 1;
		return 0 if $_[ARG2] !~ /\b(?:thank\s*you|thanks|thx|cheers)\b/i;

		my $ctx = BotIrc::ctx_frozen();
		my @nicks = map(lc, $BotIrc::irc->channel_list($ctx->{channel}));
		@nicks = grep { $_[ARG2] =~ /\b\Q$_\E\b/i; } @nicks;

		for my $n (@nicks) {
			if ($n eq lc($BotIrc::irc->nick_name())) {
				BotIrc::ctx_set_addressee(BotIrc::ctx_source());
				BotIrc::send_wisdom("you're welcome, but please note that I'm a bot. I'm not programmed to care.");
			}
			$moar_karma->($n);
			$BotDb::db->do("INSERT INTO thanks (from_nick, to_nick) VALUES(?, ?)", {}, lc(BotIrc::ctx_source()), $n);
		}

		return 1;
	},
};
