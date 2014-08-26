package VK::MP3;

use strict;
use warnings;
use utf8;

use LWP;
use LWP::Protocol::https;
use HTML::Entities;
use URI::Escape;
use JSON::XS qw/decode_json/;
use Encode;

our $VERSION = 0.09;

sub new {
  my ($class, %args) = @_;
  die 'USAGE: VK::MP3->new(login => ..., password => ...)'
    unless _valid_new_args(\%args);

  my $self = { 
      ua => _create_ua(),
      login => $args{login},
      password => $args{password},
    };
  bless $self, $class;

  die 'ERROR: login failed' unless($self->_login());

  return $self;
}

sub search {
  my ($self, $query) = @_;

  my $res = $self->{ua}->get('http://vk.com/search?c[section]=audio&c[q]='.uri_escape_utf8($query));
  die 'LWP: '.$res->status_line unless $res->is_success;

  my @matches = $res->decoded_content =~  m'<input type="hidden" id="audio_info(.*?)</tbody></table>'sgi;

  my @rslt;
  push @rslt, $self->_parse_found_item($_) for(@matches);
  @rslt = grep { defined $_ } @rslt;

  return \@rslt;
}

sub get_playlist {
  my ( $self, %args ) = @_;
  my $res;
  my $id;

  if ( defined $args{url} ) {
    if ( $args{url} =~ m#/id(\d+)$# ) {
      $id = $1;
    } else {
      $id = $self->_get_user_id( $args{url} );
    }
  } elsif ( defined $args{name} ) {
    $id = $self->_get_user_id( 'https://vk.com/' . $args{name} );
  } elsif ( defined $args{id} ) {
    $id = $args{id};
  } else {
    $id = $self->{id};
  }

  $res = $self->{ua}->post( 'http://vk.com/audio', {
      act              => 'load_audios_silent',
      al               => 1,
      gid              => 0,
      id               => $id,
      please_dont_ddos => '2',
    },
  );
  die 'LWP: ' . $res->status_line unless $res->is_success;
  
  my $json_str = ( split /<!>/, $res->decoded_content )[5];
  $json_str =~ s/'/"/gs;
  $json_str = Encode::encode( 'utf-8', $json_str );
  
  my $json;
  eval { $json = decode_json($json_str); };

  if ($@) {
    switch ($@) {
      case ('Ошибка доступа') { die $json_str }
      else { die( $json_str || '$json_str = UNDEFINED;' ) . "\n" . $@ }
    }
  }

  my $json_str_album = ( split /<!>/, $res->decoded_content )[6];
  $json_str_album =~ s/'/"/gs;
  $json_str_album = Encode::encode( 'utf-8', $json_str_album );

  my $albums;
  eval {
    $albums = decode_json($json_str_album);
    $albums = $albums->{albums};
    if ( !$albums or ref($albums) ne 'HASH' ) {
      $albums = {};
    } else {
      $albums->{$_}->{title} = decode_entities( $albums->{$_}->{title} )
        for ( keys %{$albums} );
    }
  };

  if ($@) {
    switch ($@) {
      case ('Ошибка доступа') {
        die $json_str_album . "\n" . $@
      } else {
        die( ( $json_str_album || '$json_str = UNDEFINED;' )."\n".$@ );
      }
    }
  }
  return 'Invalid response' unless defined $json->{all} && ref( $json->{all} ) eq 'ARRAY';

  my @rslt;
  for my $item ( @{ $json->{all} } ) {
    next unless ref $item eq 'ARRAY' && scalar @{$item} > 7;
    my $name = decode_entities( $item->[5] . ' – ' . $item->[6] );
    $name =~ s/(^\s+|\s+$)//g;
    my $rslt_item = {
      full_name     => $name,
      author        => decode_entities( $item->[5] ),
      name          => decode_entities( $item->[6] ),
      duration      => $item->[3],
      full_duration => $item->[4],
      link          => $item->[2],
      album         => $albums->{ $item->[8] },
    };
    push @rslt, $rslt_item;
  }
  return \@rslt;
}

sub _parse_found_item {
  my ($self, $str) = @_;
  my ($name) = $str =~ m{<div class="title_wrap fl_l".*?>(.*?)</div>}si;
  return undef unless $name;
 
  $name =~ s/<[^>]+>//g;
  $name =~ s/ ?\([^\(]*$//;
  $name = decode_entities($name);

  my ($duration) = $str =~ m{<div class="duration fl_r".*?>(\d+:\d+)</div>}i;
  my ($link) = $str =~ m{value="(http://[^",]+\.mp3)}i;

  if($duration) {
    my ($min, $sec) = split /:/, $duration, 2;
    $duration = $min * 60 + $sec;
  } else {
    $duration = 0;
  }
  
  return { name => $name, duration => $duration, link => $link };
}

sub _login {
  my $self = shift;
  my $res = $self->{ua}->post('https://login.vk.com/?act=login', {
      email => $self->{login},
      pass => $self->{password},
    });  

  if(  $res->is_success &&
      ($res->decoded_content =~ /var\s+vk\s*=\s*\{[^\{\}]*?id\s*\:\s*(\d+)/i
       || $res->decoded_content =~ m#login\.vk\.com/\?act=logout#i ) ) {
    $self->{id} = $1;
    return 1;
  }
  return 0;
}

sub _get_user_id {
  my ($self, $url) = @_;

  my $res = $self->{ua}->get($url);
  die 'LWP: '.$res->status_line unless $res->is_success;

  if ($res->content =~ m#friends\?id=(\d+)#) {
    return $1;
  }

  die "Can't get user id! LWP: ".$res->status_line."\n\n".$res->content."\n";
}

sub _create_ua {
  my $ua = LWP::UserAgent->new();

  push @{ $ua->requests_redirectable }, 'POST';
  $ua->cookie_jar( {} );

  return $ua;
}

sub _valid_new_args {
  my $args = shift;
  return 0 unless ref($args) eq 'HASH';
  for(qw/login password/) {
    return 0 unless defined($args->{$_}) && (ref($args->{$_}) eq '');
  }
  return 1;
}

1;

__END__

=head1 NAME

VK::MP3 - searches for mp3 on vkontakte.ru, also known as vk.com.

=head1 SYNOPSIS

    use VK::MP3;
     
    my $vk = VK::MP3->new(login => 'user', password => 'secret');
    
    my $rslt = $vk->search('Nightwish');
    for (@{$rslt}) {
        # $_->{name}, $_->{duration}, $_->{link}
    }
    
    my $playlist = $vk->get_playlist;
    for (@{$playlist}) {
        # $_->{name}, $_->{duration}, $_->{link}
    }

=head1 DESCRIPTION

B<VK::MP3> helps you to find direct URL's of audio files on vk.com (via regular expressions and LWP).

This package also includes B<vkmp3> utility, which allows you download found mp3 (or all files from your playlist).

=head1 METHODS

=head2 C<new>

    my $vk = VK::MP3->new(login => $login, password => $password)

Constructs a new C<VK::MP3> object and logs on vk.com. Throws exception in case of any error.

=head2 C<search>

    my $rslt = $vk->search($query)

Results, found by $query.

=head2 C<get_playlist>

    my $rslt = $vk->get_playlist()
Returns your playlist.

    my $rslt = $vk->get_playlist(url => 'http://vk.com/userLink');
Returns user playlist.

    my $rslt = $vk->get_playlist(url => 'http://vk.com/id1'); # http://vk.com/id1
Returns user playlist.

    my $rslt = $vk->get_playlist(name => 'userLink'); # http://vk.com/userLink
Returns user playlist.

    my $rslt = $vk->get_playlist(id => 1); # http://vk.com/id1
Returns user playlist.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc VK::MP3

You can also look for information at:

=over 3

=item * GitHub

L<https://github.com/afiskon/p5-vk-mp3>

=item * AnnoCPAN: Annotated CPAN documentation

L<http://annocpan.org/dist/VK-MP3>

=item * CPAN Ratings

L<http://cpanratings.perl.org/d/VK-MP3>

=back

=head1 SEE ALSO

L<VK>, L<VKontakte::API>, L<LWP::UserAgent>.

=head1 AUTHOR

Alexandr Alexeev, <eax at cpan.org> (L<http://eax.me/>)

=head1 COPYRIGHT

Copyright 2011-2012 by Alexandr Alexeev

This library is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=cut
