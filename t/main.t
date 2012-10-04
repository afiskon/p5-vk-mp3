#!/usr/bin/perl

use strict;
use warnings;
use utf8;

use Test::More;
use Test::Mock::LWP;
use HTTP::Response;
use_ok "VK::MP3";

eval { VK::MP3->new() };
like($@, qr/^USAGE:/);

my (@url_hist, @arg_hist);

$Mock_ua->mock(requests_redirectable => sub { ['GET', 'HEAD'] } );
$Mock_ua->mock($_ => sub { } ) for(qw/ssl_opts cookie_jar/);
$Mock_ua->mock($_ => sub {
    my ($mock, $url, $args) = @_;
    push @url_hist, $url;
    push @arg_hist, $args;
    return HTTP::Response->new();
  }) for qw/post get/;
$Mock_resp->mock(is_success => sub { 0 } );

eval { VK::MP3->new(login => 123, password => 456) };
cmp_ok($url_hist[-1], 'eq', 'https://login.vk.com/?act=login');
cmp_ok($arg_hist[-1]->{email}, '==', 123);
cmp_ok($arg_hist[-1]->{pass}, '==', 456);
like($@, qr/^ERROR: login failed/);

$Mock_resp->mock(is_success => sub { 1 } );
$Mock_resp->mock(decoded_content => sub { 'bebeb' } );

eval { VK::MP3->new(login => 456, password => 789) };
cmp_ok($url_hist[-1], 'eq', 'https://login.vk.com/?act=login');
cmp_ok($arg_hist[-1]->{email}, '==', 456);
cmp_ok($arg_hist[-1]->{pass}, '==', 789);
like($@, qr/^ERROR: login failed/);

$Mock_resp->mock(decoded_content => sub { 'bebebe var vk = { xxx : 123, id: 1234 }; bebebe' } );

my $vk = eval { VK::MP3->new(login => 321, password => 654) };
cmp_ok($@, 'eq', '');
isa_ok($vk, 'VK::MP3');

$Mock_resp->mock(is_success => sub { 0 });
$Mock_resp->mock(status_line => sub { '__MOCK_STATUS_LINE__' });

eval { $vk->search('Nightwish') };
like($@, qr/^LWP: __MOCK_STATUS_LINE__/);

$Mock_resp->mock(is_success => sub { 1 });
{
  my $rslt = eval { $vk->search('ДДТ - Метель') };
  cmp_ok($@, 'eq', '');
  cmp_ok(ref($rslt), 'eq', 'ARRAY');
  cmp_ok(scalar(@{$rslt}), '==', 0);
}

$Mock_resp->mock(decoded_content => sub {q{
      <input type="hidden" id="audio_info8087439_88606104_1" value="http://cs1234.userapi.com/FAKE/AUDIO/URL/1.mp3,206" />
      <td class="info">
        <div class="duration fl_r" onmousedown="if (window.audioPlayer) audioPlayer.switchTimeFormat('19485673_70511433_36', event);">3:08</div>
        <div class="title_wrap fl_l"><b><a href="/search?section=audio&c[q]=%CA%E8%EF%E5%EB%EE%E2" onclick="return nav.go(this, event);"><span class="match">Кипелов</span></a></b> &ndash; <span id="title19485673_70511433_36"><a href="#" onclick="searchActions.showLyrics('19485673_70511433_36',3274073,0); return false;">Я свободен&#33;</a></span> <span class="user">(<a href="/id19485673" onclick="return nav.go(this, event);">А. Базалеева</a>)</span></div>
      </tbody></table>
      <input type="hidden" id="audio_info8087439_88606104_1" value="http://cs1234.userapi.com/FAKE/AUDIO/URL/2.mp3,206" />
      <td class="info">
        <div class="duration fl_r" onmousedown="if (window.audioPlayer) audioPlayer.switchTimeFormat('5211410_97970670_6', event);">4:47</div>
        <div class="title_wrap fl_l"><b><a href="/search?section=audio&c[q]=%CA%E8%EF%E5%EB%EE%E2" onclick="return nav.go(this, event);"><span class="match">Кипелов</span></a></b> &ndash; <span id="title5211410_97970670_6"><a href="#" onclick="searchActions.showLyrics('5211410_97970670_6',9346042,0); return false;">Власть Огня</a></span> <span class="user">(<a href="/dark_katarios" onclick="return nav.go(this, event);">Е. Юлина</a>)</span></div>
      </tbody></table>
      <input type="hidden" id="audio_info8087439_88606104_1" value="http://cs1234.userapi.com/FAKE/AUDIO/URL/3.mp3,206" />
      <td class="info">
        <div class="title_wrap fl_l"><b><a href="/search?section=audio&c[q]=%C1%E8%202%20%E8%20%CA%E8%EF%E5%EB%EE%E2" onclick="return nav.go(this, event);">Би 2 и <span class="match">Кипелов</span></a></b> &ndash; <span id="title12405979_93663456_14"><a href="#" onclick="searchActions.showLyrics('12405979_93663456_14',7043992,0); return false;">Легион</a></span> <span class="user">(<a href="/apostol_666" onclick="return nav.go(this, event);">А. Абрамов</a>)</span></div>
      </tbody></table>
  }});


{
  my @exp_duration = (3 * 60 + 8, 4 * 60 + 47, 0);
  my @exp_name = (
    'Кипелов – Я свободен!',
    'Кипелов – Власть Огня',
    'Би 2 и Кипелов – Легион',
  );

  my $rslt = eval { $vk->search('Кипелов') };
  cmp_ok($@, 'eq', '');
  check_result($rslt, \@exp_name, \@exp_duration);
}

$Mock_resp->mock(decoded_content => sub { q^<!--10576<!>audio.css,audio.js<!>0<!>6339<!>0<!>{"all":[
['123456789','987654321','http://cs1234.userapi.com/FAKE/AUDIO/URL/1.mp3','233','3:53','Sonata Arctica','Kingdom For A Heart','285281','0','0','','0','1'],
['123456789','987654321','http://cs1234.userapi.com/FAKE/AUDIO/URL/2.mp3','349','5:49','Sonata Arctica','Don&#39;t Say A Word','10198377','0','0','','0','1'],
['123456789','987654321','http://cs1234.userapi.com/FAKE/AUDIO/URL/3.mp3','209','3:29',' Noize MC','Давай приколемся','0','0','0','','0','1']]
}<!>{"summaryLang":{
  "list_no":"Нет аудиозаписей",
  "list":["","%s аудиозапись","%s аудиозаписи","%s аудиозаписей"],
  "list_found":["","В поиске найдена %s аудиозапись","В поиске найдено %s аудиозаписи","В поиске найдено %s аудиозаписей"],
  "all_friend_title":"У Александра {audios_count}",
  "all_friend_htitle":"Аудиозаписи Александра"
},"albums":{"27516555":{"id":"27516555","title":"Музыка (почти) без слов"}},
"hashes":{
  "add_hash":"151339cae92292bb68",
  "delete_hash":"3e42ff420bb0a132b3",
  "restore_hash":"2211fcfcf53c901579",
  "edit_hash":"9b8d8cbf9c89ef3ede",
  "reorder_hash":"f310f7511b3cafb8f9",
  "move_hash":"1d7f27ca40eb7c301d",
  "delete_album_hash":"43ff28eff542929979",
  "save_album_hash":"36a6762c64ae5c6955"
},"exp":true}^ } );

{
  my @exp_duration = (233, 349, 209);
  my @exp_name = (
    'Sonata Arctica – Kingdom For A Heart',
    "Sonata Arctica – Don't Say A Word",
    'Noize MC – Давай приколемся',
  );


  my $rslt = eval { $vk->get_playlist() };
  cmp_ok( $@, 'eq', '');
  check_result($rslt, \@exp_name, \@exp_duration);
}

done_testing;

sub check_result {
  my ($rslt, $exp_name, $exp_duration) = @_;
  cmp_ok(ref($rslt), 'eq', 'ARRAY');
  cmp_ok(scalar(@{$rslt}), '==', 3);

  for my $i (0..2) {
    cmp_ok(ref($rslt->[$i]), 'eq', 'HASH');
    for(qw/link duration name/) {
      ok(defined $rslt->[$i]{$_});
      cmp_ok(ref($rslt->[$i]{$_}), 'eq', '');
    }
    cmp_ok($rslt->[$i]{link}, 'eq', 'http://cs1234.userapi.com/FAKE/AUDIO/URL/'.($i+1).'.mp3');
    cmp_ok($rslt->[$i]{duration}, '==', $exp_duration->[$i]);
    cmp_ok($rslt->[$i]{name}, 'eq', $exp_name->[$i]);
  }
}
